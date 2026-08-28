# frozen_string_literal: true

# Leitura do plano que o modelo escreveu, em Plan-and-Solve.
#
# Separado do agente pelo mesmo motivo que o `ReactParser`: aqui é só sintaxe.
# O modelo numera com ponto, com parêntese, escreve "Passo 1:", usa traço,
# cerca tudo em crase e ainda enfia um parágrafo de introdução antes da lista.
# Dá para cobrir essa bagunça toda sem montar um agente inteiro.
#
# Linha que não é item de lista é descartada — inclusive a introdução. E texto
# sem nenhum item devolve plano vazio em vez de virar um passo só com a prosa
# inteira dentro: prosa não é passo, e o agente sabe o que fazer com o vazio.
class PlanParser
  SPACE = /[ \t]*/.source
  LABEL = /(?:passos?|etapas?)[ \t]*/i.source
  MARKER = /(?:\d+[.)\-–:]|[-*•])/.source
  STEP = /^#{SPACE}(?:#{LABEL})?#{MARKER}#{SPACE}(.+?)#{SPACE}$/i
  FENCE = /^#{SPACE}```\w*#{SPACE}$/

  def parse(text)
    lines(text).filter_map { |line| line[STEP, 1] }
  end

  private

  def lines(text)
    text.to_s.lines.grep_v(FENCE)
  end
end
