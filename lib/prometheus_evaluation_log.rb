# frozen_string_literal: true

# Publica as notas de avaliação no registro de métricas, cumprindo a mesma
# interface do `EvaluationLog` — `record(question:, answer:, scores:)`. Entra no
# `EvaluatedRag` no lugar dele, ou ao lado, sem que o decorador saiba a
# diferença.
#
# Três decisões definem o comportamento:
#
# - **Histograma, não média.** A média de sustentação esconde o que interessa:
#   noventa respostas perfeitas e dez inventadas dão 0,9, que parece ótimo. A
#   distribuição mostra a segunda corcova. E o `_sum` com o `_count` continua
#   dando a média para quem quiser.
# - **Pergunta e resposta não viram métrica.** Só a nota atravessa. Texto de
#   usuário como rótulo seria cardinalidade infinita — e, pior, o conteúdo da
#   pergunta acabaria guardado para sempre num sistema que ninguém trata como
#   base de dados pessoais. O texto fica no log e no `EvaluationLog`, que são
#   os lugares certos para lê-lo.
# - **Frase não sustentada tem contador próprio.** A nota diz o quanto piorou;
#   o contador diz quantas afirmações sem apoio saíram para o usuário, que é o
#   número que se leva para uma conversa sobre risco.
class PrometheusEvaluationLog
  SCORES = {
    groundedness: 'aiad_llm_groundedness',
    answer_relevancy: 'aiad_llm_answer_relevancy',
    context_relevancy: 'aiad_llm_context_relevancy'
  }.freeze

  EVALUATED = 'aiad_llm_evaluated_answers_total'
  UNSUPPORTED = 'aiad_llm_unsupported_sentences_total'

  # Notas vão de 0 a 1, e os buckets são apertados perto de 1 de propósito: a
  # diferença entre 0,95 e 1,0 é a que importa, e entre 0,1 e 0,2 não é.
  BUCKETS = [0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1.0].freeze

  HELP = {
    groundedness: 'Fração das frases da resposta sustentadas pelo contexto.',
    answer_relevancy: 'Quanto a resposta trata da pergunta feita.',
    context_relevancy: 'Quanto do contexto recuperado tem a ver com a pergunta.'
  }.freeze

  def self.install(registry)
    SCORES.each { |score, name| registry.histogram(name, help: HELP.fetch(score), buckets: BUCKETS) }
    registry.counter(EVALUATED, help: 'Respostas avaliadas.')
    registry.counter(UNSUPPORTED, help: 'Frases que saíram sem apoio no contexto.')

    registry
  end

  def initialize(registry:)
    @registry = registry
  end

  # `question` e `answer` chegam e não são usados de propósito: a assinatura é
  # a do `EvaluationLog`, e é ela que permite trocar um pelo outro. Usar o
  # texto aqui é justamente o que não se quer.
  def record(question:, answer:, scores:)
    SCORES.each { |score, name| @registry.observe(name, scores[score].to_f) if scores.key?(score) }
    @registry.increment(EVALUATED)
    @registry.increment(UNSUPPORTED, by: scores[:unsupported].to_a.size)
  end
end
