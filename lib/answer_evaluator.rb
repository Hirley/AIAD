# frozen_string_literal: true

require_relative 'stemmer'

# Avaliação de qualidade da resposta: o quanto ela se sustenta no contexto
# recuperado (alucinação) e o quanto ela e o contexto têm a ver com a pergunta
# (relevância).
#
# São três notas, porque as falhas são diferentes e o conserto também. Nota de
# sustentação baixa é o modelo inventando; relevância de contexto baixa é a
# recuperação trazendo lixo; relevância de resposta baixa é o modelo respondendo
# outra pergunta.
#
# Sete decisões que definem o comportamento:
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
#   qualquer trecho e dariam sustentação a qualquer invenção. A lista mora no
#   `Tokenizer`, junto com o resto do que define o que é um termo, porque o
#   `RelevanceFloor` depende dela pelo mesmo motivo — e duas listas divergiriam.
# - **A lista das frases reprovadas sai junto.** O número diz que piorou; a
#   lista diz o que ler.
# - **Relevância de contexto é média de sobreposição, não contagem de trechos
#   que sobrepõem.** A versão contada chamava o trecho de relevante com
#   sobreposição *maior que zero* — e o `RelevanceFloor`, que roda antes, só
#   deixa passar trecho a partir de 0,45. Passar no piso implicava passar aqui,
#   e a nota só conseguia valer 1,0: cinco amostras na stack, cinco vezes 1,0;
#   dezesseis mil perguntas geradas, um único valor. A métrica que existe para
#   avisar "a recuperação está trazendo lixo" tinha perdido a capacidade de
#   avisar, porque quem define lixo é a mesma conta que o piso usou para
#   manter. A média não desfaz esse parentesco — devolve a informação: piso mal
#   calibrado mantendo trecho a 0,45 agora aparece como 0,45 no painel.
# - **Sustentação é sobreposição de vocabulário, e isso tem um limite medido.**
#   Uma paráfrase correta e uma alucinação podem tirar a mesma nota, porque
#   nenhuma das duas reaproveita as palavras do trecho. Medido contra o acervo
#   deste projeto: paráfrase certa tirou 0,11 e alucinação pura tirou 0,17 — as
#   faixas se **sobrepõem**, e por isso nenhum ajuste de `SUPPORT_THRESHOLD`
#   resolve. Hoje não dói, porque o `ExtractiveLlm` recorta o trecho em vez de
#   reescrevê-lo e a resposta é substring literal do contexto. Dói no dia em
#   que entrar um modelo que parafraseia, e o sintoma será a nota desabando ao
#   acusar de alucinação resposta correta. A saída é o `judge:`, não o limiar.
class AnswerEvaluator
  SUPPORT_THRESHOLD = 0.6
  SENTENCE = /(?<=[.!?])\s+/

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

    passages.sum { |passage| overlap(question, passage[:text]) }.fdiv(passages.size)
  end

  def content_terms(text)
    Stemmer.meaningful_stems(text).uniq
  end

  # Fragmento sem letra nenhuma não é afirmação, e por isso não entra na conta.
  # O caso concreto é o marcador de citação: "…trinta dias. [1]" quebra em três
  # pedaços, e o "[1]" sozinho ficava marcado como não sustentado. O efeito era
  # perverso — toda resposta **corretamente citada** perdia um terço da nota,
  # justamente por fazer o que se pede que ela faça.
  def sentences_of(answer)
    answer.to_s.split(SENTENCE).map(&:strip).select { |sentence| claim?(sentence) }
  end

  def claim?(sentence)
    sentence.match?(/[[:alpha:]]/)
  end
end
