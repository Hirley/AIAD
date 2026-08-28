# frozen_string_literal: true

require_relative 'usage_meter'

# Latência, custo e tokens por sessão — a conta que responde "quem está
# gastando o quê, e quanto tempo está esperando".
#
# O `UsageMeter` já sabe converter tokens em dinheiro e quebrar por modelo.
# Aqui se acrescenta a dimensão que faltava (a sessão, ou o usuário, se for ele
# que rotula) e a latência, que o medidor de uso não tem como conhecer.
#
# Quatro decisões que definem o comportamento:
#
# - **A latência é a da requisição inteira, não a de cada chamada de modelo.**
#   Um agente faz várias chamadas para responder uma pergunta; o que o usuário
#   sente é a soma, mais o tempo de ferramenta e de busca no meio.
# - **O custo vem do medidor.** O preço por milhão de tokens já mora lá;
#   recalcular aqui seria criar um segundo lugar para errar.
# - **Requisição sem rótulo entra num balde próprio.** Perder a medição por
#   falta de sessão é pior do que medi-la separada.
# - **Sessão desconhecida devolve zero, não erro.** Dashboard pergunta por
#   sessão que ainda não existe o tempo todo.
class SessionMetrics
  NO_SESSION = 'sem-sessão'
  P95 = 0.95

  def initialize(meter: UsageMeter.new)
    @meter = meter
    @sessions = Hash.new { |sessions, key| sessions[key] = empty_bucket }
  end

  def record(model:, prompt_tokens:, completion_tokens:, latency:, session: nil)
    usage = @meter.record(model: model, prompt_tokens: prompt_tokens, completion_tokens: completion_tokens)
    accumulate(@sessions[label(session)], usage, latency)

    usage
  end

  def for_session(session)
    summarize(@sessions.fetch(label(session), empty_bucket))
  end

  def sessions
    @sessions.keys
  end

  def totals
    summarize(@sessions.values.each_with_object(empty_bucket) { |bucket, sum| merge(sum, bucket) })
  end

  def by_model
    @meter.by_model
  end

  private

  def accumulate(bucket, usage, latency)
    bucket[:requests] += 1
    bucket[:prompt_tokens] += usage[:prompt_tokens]
    bucket[:completion_tokens] += usage[:completion_tokens]
    bucket[:total_tokens] += usage[:total_tokens]
    bucket[:cost] += usage[:cost]
    bucket[:latencies] << latency.to_f
  end

  def merge(sum, bucket)
    sum[:requests] += bucket[:requests]
    sum[:prompt_tokens] += bucket[:prompt_tokens]
    sum[:completion_tokens] += bucket[:completion_tokens]
    sum[:total_tokens] += bucket[:total_tokens]
    sum[:cost] += bucket[:cost]
    sum[:latencies].concat(bucket[:latencies])
    sum
  end

  def summarize(bucket)
    bucket.slice(:requests, :prompt_tokens, :completion_tokens, :total_tokens, :cost)
          .merge(latency: latency_of(bucket[:latencies]))
  end

  def latency_of(samples)
    return { total: 0.0, average: 0.0, max: 0.0, p95: 0.0 } if samples.empty?

    total = samples.sum

    { total: total, average: total / samples.size, max: samples.max, p95: percentile(samples, P95) }
  end

  # Nearest rank: com poucas amostras o p95 vira a maior delas, e é isso mesmo.
  # Interpolar daria um número mais bonito e igualmente sem significado.
  def percentile(samples, fraction)
    sorted = samples.sort

    sorted[(fraction * sorted.size).ceil - 1]
  end

  def label(session)
    value = session.to_s.strip

    value.empty? ? NO_SESSION : value
  end

  def empty_bucket
    { requests: 0, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0, cost: 0.0, latencies: [] }
  end
end
