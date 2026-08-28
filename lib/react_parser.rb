# frozen_string_literal: true

# Leitura da resposta do modelo no formato ReAct.
#
# Separado do agente de propósito: aqui é só sintaxe — o que o modelo escreveu.
# Decidir o que fazer com isso é do agente. Dá para testar todo tipo de saída
# torta sem montar um laço inteiro.
#
# Duas defesas contra o vício mais comum do modelo, que é escrever a
# trajetória inteira sozinho:
#
# 1. Corta na primeira "Observação:" — observação quem produz é a ferramenta.
# 2. Se vierem ação e resposta final juntas, a ação ganha. Responder junto com
#    a ação é responder antes de ver o resultado.
#
# As etiquetas usam espaço horizontal (`[ \t]`) e não `\s`, que engoliria a
# quebra de linha e faria uma etiqueta vazia capturar a linha seguinte.
class ReactParser
  SPACE = /[ \t]*/.source
  THOUGHT = /^#{SPACE}Pensamento#{SPACE}:#{SPACE}(.+?)#{SPACE}$/i
  ACTION = /^#{SPACE}A(?:ção|cao)#{SPACE}:#{SPACE}(.*)$/i
  INPUT = /^#{SPACE}Entrada#{SPACE}:#{SPACE}(.*)\z/im
  ANSWER = /^#{SPACE}Resposta[ \t]+Final#{SPACE}:#{SPACE}(.*)\z/im
  OBSERVATION = /^#{SPACE}Observa(?:ção|cao)#{SPACE}:/i

  def parse(text)
    body = truncate_at_observation(text.to_s)
    thought = body[THOUGHT, 1]

    step(body, thought) || { type: :unknown, thought: thought, raw: text.to_s }
  end

  private

  def step(body, thought)
    action(body, thought) || answer(body, thought)
  end

  def action(body, thought)
    tool = body[ACTION, 1].to_s.strip
    return nil if tool.empty?

    { type: :action, thought: thought, tool: tool, input: input_after(body) }
  end

  def answer(body, thought)
    text = body[ANSWER, 1].to_s.strip
    return nil if text.empty?

    { type: :answer, thought: thought, answer: text }
  end

  # A entrada é o resto do texto depois de "Entrada:", porque JSON de várias
  # linhas é comum. O que vier depois de outra etiqueta já foi cortado.
  def input_after(body)
    value = body[INPUT, 1].to_s.split(ANSWER).first.to_s.strip

    value.empty? ? nil : value
  end

  def truncate_at_observation(text)
    text.split(OBSERVATION).first.to_s
  end
end
