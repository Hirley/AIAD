# frozen_string_literal: true

# Modelo de resposta extrativa: devolve, sem reescrever, o trecho mais relevante
# do contexto montado pelo PromptBuilder.
#
# Existe para que a API funcione de ponta a ponta sem nenhuma credencial de
# provedor de LLM — é um substituto honesto, não um gerador: ele nunca inventa
# conteúdo, só recorta. Para respostas geradas de verdade, injete um modelo real
# no RagPipeline; a interface é a mesma (`complete(prompt)`).
class ExtractiveLlm
  NO_ANSWER = 'Não encontrei essa informação nos documentos indexados.'
  FIRST_PASSAGE = /^\[1\]\s+\(origem:[^)]*\)\n(.+?)(?:\n\s*\n|\z)/m
  MODEL = 'extrativo'

  # Se diz pelo nome, como um modelo real: assim a métrica de custo distingue
  # "rodando no extrativo" de "rodando num modelo pago", que é a primeira coisa
  # que se pergunta ao olhar uma conta.
  def model
    MODEL
  end

  def complete(prompt)
    match = FIRST_PASSAGE.match(prompt.to_s)
    return NO_ANSWER if match.nil?

    "#{match[1].strip} [1]"
  end
end
