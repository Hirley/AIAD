# frozen_string_literal: true

# Acumula as notas de qualidade ao longo do tempo: a média de cada uma e as
# respostas que pontuaram pior.
#
# Duas decisões que definem o comportamento:
#
# - **A média é corrente e não cresce.** Guardar toda avaliação para depois
#   dividir vazaria memória num serviço que roda semanas. Somas e contagem
#   bastam.
# - **Só as piores ficam guardadas, e em número fixo.** A média diz que a
#   qualidade caiu; a lista diz o que ler para descobrir por quê. Guardar as
#   boas não ajuda ninguém e é o que faria o log crescer sem limite.
class EvaluationLog
  DEFAULT_KEEP = 20
  SCORES = %i[groundedness answer_relevancy context_relevancy].freeze

  def initialize(keep: DEFAULT_KEEP)
    @keep = keep
    @samples = 0
    @sums = SCORES.to_h { |score| [score, 0.0] }
    @worst = []
  end

  def record(question:, answer:, scores:)
    @samples += 1
    SCORES.each { |score| @sums[score] += scores[score].to_f }
    remember(question, answer, scores)

    scores
  end

  def averages
    return @sums.transform_values { 0.0 }.merge(samples: 0) if @samples.zero?

    @sums.transform_values { |sum| sum / @samples }.merge(samples: @samples)
  end

  def worst(limit = @keep)
    @worst.first(limit)
  end

  private

  def remember(question, answer, scores)
    @worst << { question: question, answer: answer, scores: scores,
                groundedness: scores[:groundedness].to_f }
    @worst.sort_by! { |entry| entry[:groundedness] }
    @worst.pop while @worst.size > @keep
  end
end
