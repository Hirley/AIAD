# frozen_string_literal: true

require_relative 'usage_meter'

# Exportador de trace que publica tokens, custo e latência de modelo direto no
# registro de métricas.
#
# É irmão do `MetricsExporter`, que alimenta o `SessionMetrics` em memória, e
# existe separado por um motivo concreto: o `SessionMetrics` guarda uma entrada
# por chamada e uma por sessão, e num serviço que roda semanas isso cresce sem
# limite. Quem guarda série temporal é o Prometheus. Aqui a memória é fixa —
# um punhado de séries, não importa quantas perguntas cheguem.
#
# Quatro decisões definem o comportamento:
#
# - **Mede o span que gastou token, não a raiz.** O span que carrega `usage` é
#   o da geração; a raiz inclui recuperação, compressão e montagem de prompt.
#   Chamar aquilo de "latência do modelo" seria culpar o modelo pelo tempo da
#   busca. E como a varredura é na árvore inteira, um agente que chama o modelo
#   cinco vezes rende cinco observações, não uma média achatada.
# - **Sem acoplar a nome de span.** O critério é ter `usage`, não se chamar
#   `rag.generate`. Renomear um span não pode apagar a métrica.
# - **Pergunta sem contexto não é chamada de modelo.** Quando nada é
#   recuperado, o pipeline responde sem chamar o modelo e o uso é zero. Contar
#   isso como chamada afundaria o custo médio e mentiria sobre quantas vezes o
#   modelo foi acionado.
# - **Custo sai da mesma conta do `UsageMeter`.** Duas definições de "quanto
#   custou" divergiriam na primeira mudança de tabela de preço.
class PrometheusTraceExporter
  CALLS = 'aiad_llm_calls_total'
  PROMPT_TOKENS = 'aiad_llm_prompt_tokens_total'
  COMPLETION_TOKENS = 'aiad_llm_completion_tokens_total'
  COST = 'aiad_llm_cost_usd_total'
  LATENCY = 'aiad_llm_latency_seconds'
  UNKNOWN_MODEL = 'desconhecido'

  # Buckets em segundos, na escala de uma chamada de modelo: de resposta local
  # rápida a geração longa que ainda não estourou timeout.
  BUCKETS = [0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60].freeze

  def self.install(registry)
    registry.counter(CALLS, help: 'Chamadas ao modelo.', labels: %i[model])
    registry.counter(PROMPT_TOKENS, help: 'Tokens gastos em prompt.', labels: %i[model])
    registry.counter(COMPLETION_TOKENS, help: 'Tokens gastos em resposta.', labels: %i[model])
    registry.counter(COST, help: 'Custo acumulado em dólares.', labels: %i[model])
    registry.histogram(LATENCY, help: 'Duração das chamadas ao modelo, em segundos.',
                                labels: %i[model], buckets: BUCKETS)

    registry
  end

  def initialize(registry:, prices: {})
    @registry = registry
    @prices = prices
  end

  def export(trace)
    billable(trace, model_of(trace, UNKNOWN_MODEL)).each { |call| record(call) }
  end

  private

  # Percorre a árvore inteira e devolve uma entrada por span que gastou token.
  # O modelo é herdado do span de cima quando o span não declara o seu.
  def billable(span, inherited)
    model = model_of(span, inherited)
    usage = span[:usage] || {}
    own = spent?(usage) ? [{ model: model, usage: usage, duration: span[:duration].to_f }] : []

    own + (span[:spans] || []).flat_map { |nested| billable(nested, model) }
  end

  def record(call)
    labels = { model: call[:model] }
    prompt_tokens = call[:usage][:prompt_tokens].to_i
    completion_tokens = call[:usage][:completion_tokens].to_i

    @registry.increment(CALLS, labels: labels)
    @registry.increment(PROMPT_TOKENS, labels: labels, by: prompt_tokens)
    @registry.increment(COMPLETION_TOKENS, labels: labels, by: completion_tokens)
    @registry.increment(COST, labels: labels,
                              by: UsageMeter.cost_of(@prices, call[:model], prompt_tokens, completion_tokens))
    @registry.observe(LATENCY, call[:duration], labels: labels)
  end

  def spent?(usage)
    usage[:prompt_tokens].to_i.positive? || usage[:completion_tokens].to_i.positive?
  end

  def model_of(span, fallback)
    model = (span[:metadata] || {})[:model]

    model.nil? || model.to_s.empty? ? fallback : model.to_s
  end
end
