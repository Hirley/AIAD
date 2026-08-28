# frozen_string_literal: true

require_relative 'tokenizer'

# Avaliação de qualidade da resposta: o quanto ela se sustenta no contexto
# recuperado (alucinação) e o quanto ela e o contexto têm a ver com a pergunta
# (relevância).
#
# São três notas, porque as falhas são diferentes e o conserto também. Nota de
# sustentação baixa é o modelo inventando; relevância de contexto baixa é a
# recuperação trazendo lixo; relevância de resposta baixa é o modelo respondendo
# outra pergunta.
#
# Cinco decisões que definem o comportamento:
#
# - **Heurística barata por padrão, juiz injetável.** Mesmo desenho do
#   `Reranker`: sobreposição de termos roda em toda resposta sem custo e sem
#   rede, e um LLM-as-judge ou cross-encoder entra por injeção sem mexer em
#   quem chama. Avaliação contínua que gasta uma chamada de modelo por resposta
#   não sobrevive ao primeiro pico de tráfego.
# - **Pontuação por sentença, não pelo texto inteiro.** Três frases certas e uma
#   inventada precisam dar 0,75. É o grau que mostra a qualidade caindo; um
#   booleano só acende quando já está ruim.
# - **Sem contexto, sustentação é zero.** Afirmar sem nada em que se apoiar é
#   não-sustentado por definição. Devolver 1 por vacuidade esconderia o caso
#   exato que a métrica existe para pegar. (Quem decide não avaliar a resposta
#   de "não encontrei" é quem chama, que sabe se o modelo chegou a ser usado.)
# - **Palavra funcional não sustenta nada.** "de", "para", "com" aparecem em
#   qualquer trecho e dariam sustentação a qualquer invenção.
# - **A lista das frases reprovadas sai junto.** O número diz que piorou; a
#   lista diz o que ler.
class AnswerEvaluator
  SUPPORT_THRESHOLD = 0.6
  SENTENCE = /(?<=[.!?])\s+/

  # Lista curta de propósito: só as palavras funcionais mais comuns do
  # português. Lista grande começa a derrubar termo que importa.
  #
  # As interrogativas estão aqui por um motivo específico: "quantos", "quando",
  # "qual" nunca aparecem na resposta, e sem tirá-las da conta toda resposta
  # boa perderia pontos por não repetir a palavra da pergunta.
  STOPWORDS = %w[
    a ao aos as às com como da das de do dos e em entre me na nas no nos num numa o os ou para pela pelas
    pelo pelos por que se sem ser sob sobre um uma umas uns é são foi era está estão têm tem
    onde qual quais quando quanta quantas quanto quantos quem quê
  ].freeze
  def initialize(judge: nil, threshold: SUPPORT_THRESHOLD)
    @judge = judge
    @threshold = threshold
  end

  def evaluate(question:, answer:, passages:)
    context = passages.map { |passage| passage[:text].to_s }.join(' ')
    sentences = sentences_of(answer)
    unsupported = sentences.reject { |sentence| supported?(sentence, context) }

    { groundedness: groundedness(sentences, unsupported, context), unsupported: unsupported,
      sentences: sentences.size, answer_relevancy: overlap(question, answer),
      context_relevancy: context_relevancy(question, passages) }
  end

  private

  def groundedness(sentences, unsupported, context)
    return 0.0 if sentences.empty? || context.strip.empty?

    (sentences.size - unsupported.size).fdiv(sentences.size)
  end

  def supported?(sentence, context)
    return false if context.strip.empty?
    return @judge.call(sentence, context).to_f >= @threshold if @judge

    overlap(sentence, context) >= @threshold
  end

  # Fração dos termos de conteúdo do primeiro texto que aparecem no segundo.
  def overlap(text, against)
    terms = content_terms(text)
    return 0.0 if terms.empty?

    target = content_terms(against)

    (terms & target).size.fdiv(terms.size)
  end

  def context_relevancy(question, passages)
    return 0.0 if passages.empty?

    related = passages.count { |passage| overlap(question, passage[:text]).positive? }

    related.fdiv(passages.size)
  end

  def content_terms(text)
    (Tokenizer.tokens(text) - STOPWORDS).uniq
  end

  def sentences_of(answer)
    answer.to_s.split(SENTENCE).map(&:strip).reject(&:empty?)
  end
end
