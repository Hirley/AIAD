# frozen_string_literal: true

require 'set'

require_relative 'stemmer'

# Piso de relevância: descarta os trechos que não têm a ver com a pergunta.
#
# Existe por causa de um defeito concreto, encontrado rodando a stack e não
# lendo o código. Perguntada sobre um assunto que não estava em documento
# nenhum ("qual a política de plano odontológico"), a API respondia com a
# política de férias, citando a origem, com toda a convicção de uma resposta
# certa. O recuperador devolve o top-k por construção — por pior que seja o
# melhor —, e sem um piso o pipeline trata "o menos ruim" como "o certo".
#
# Quatro decisões definem o comportamento:
#
# - **O piso não pode se apoiar no score da busca híbrida.** O RRF pontua por
#   *posição*, não por qualidade: 1/(k + posição). Um documento em primeiro
#   lugar nos dois braços vale sempre o mesmo, seja ele a resposta exata ou o
#   único lixo de um acervo irrelevante. Medido na stack real, `politica-ferias`
#   tirou exatamente `0.03278688524590164` tanto para "quantos dias de férias
#   por ano" quanto para "plano de saúde odontológico" — o mesmo número até o
#   último dígito. Qualquer limiar sobre esse score seria um limiar sobre nada.
# - **Por isso o piso mede de novo, e mede outra coisa:** quantos termos de
#   conteúdo da pergunta aparecem no trecho. É uma escala 0..1 que fala de
#   casamento, não de ranking.
# - **Palavra funcional não conta.** Foi o achado que fez o piso funcionar:
#   medindo com "qual", "a", "de" na conta, pergunta sem resposta no acervo
#   tirava 0,50 e pergunta respondível também — as duas faixas se sobrepunham e
#   não havia limiar que as separasse. Tirando as funcionais, as respondíveis
#   ficaram em 0,50–1,00 e as sem resposta em 0,00–0,33.
# - **Recusar é responder.** Devolver lista vazia faz o `RagPipeline` cair no
#   caminho que já existia para "não recuperei nada", que responde "Não
#   encontrei essa informação nos documentos indexados" e nem chama o modelo.
#   Uma recusa explícita é mais útil que uma resposta confiante e errada, e de
#   quebra não é avaliada — o `EvaluatedRag` ignora resposta sem contexto, então
#   recusar não suja o histograma de qualidade.
class RelevanceFloor
  # Calibrado, recalibrado depois do stemming, e o resultado da segunda vez
  # vale mais do que o número: **as faixas se sobrepõem**.
  #
  # Em catorze perguntas contra três documentos, as respondíveis ficaram em
  # 0,20–1,00 e as sem resposta em 0,00–0,33. Na primeira medição, com onze
  # perguntas, parecia haver um vão limpo entre 0,33 e 0,50 — duas perguntas a
  # mais desfizeram essa impressão. "posso pedir adiantamento antes de viajar"
  # é respondível e tira 0,20, abaixo de duas perguntas que o acervo não
  # cobre. **Nenhum valor separa esses dois casos**, porque só um dos quatro
  # termos de conteúdo da pergunta aparece no documento; é limite da cobertura
  # léxica, não do limiar.
  #
  # 0,45 acerta treze das catorze e é o que fica. Não é a fronteira entre certo
  # e errado — é onde o erro custa menos. O número a observar em produção é a
  # taxa de recusa: subindo sem motivo, o piso está alto; pergunta sem resposta
  # sendo respondida, está baixo.
  DEFAULT_MINIMUM = 0.45

  def initialize(minimum: DEFAULT_MINIMUM, scorer: nil)
    @minimum = minimum
    @scorer = scorer || method(:coverage)
  end

  def apply(question, passages)
    passages.select { |passage| @scorer.call(question, passage[:text].to_s).to_f >= @minimum }
  end

  private

  # Sem termo de conteúdo na pergunta não há o que casar. Devolver 1 por
  # vacuidade aprovaria qualquer trecho para qualquer pergunta — que é
  # exatamente o defeito que esta classe existe para corrigir.
  def coverage(question, text)
    terms = Stemmer.meaningful_stems(question).uniq
    return 0.0 if terms.empty? || text.empty?

    present = Stemmer.stems(text).to_set

    terms.count { |term| present.include?(term) }.fdiv(terms.size)
  end
end
