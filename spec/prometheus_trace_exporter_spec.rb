# frozen_string_literal: true

require_relative '../lib/metric_registry'
require_relative '../lib/prometheus_trace_exporter'
require_relative '../lib/tracer'

RSpec.describe PrometheusTraceExporter do
  let(:registry) { described_class.install(MetricRegistry.new) }
  let(:prices) { { 'gpt-forte' => { input: 1000.0, output: 2000.0 } } }

  subject(:exporter) { described_class.new(registry: registry, prices: prices) }

  def trace_with(spans, metadata: {})
    { name: 'rag.answer', duration: 9.0, metadata: metadata, usage: nil, spans: spans }
  end

  def generation(prompt: 100, completion: 50, duration: 2.0, metadata: {})
    { name: 'rag.generate', duration: duration, metadata: metadata, spans: [],
      usage: { prompt_tokens: prompt, completion_tokens: completion, total_tokens: prompt + completion } }
  end

  describe 'tokens e chamadas' do
    before { exporter.export(trace_with([generation], metadata: { model: 'gpt-forte' })) }

    it 'counts the call' do
      expect(registry.render).to include(%(aiad_llm_calls_total{model="gpt-forte"} 1\n))
    end

    it 'counts prompt and completion tokens apart, because they custam preços diferentes' do
      expect(registry.render).to include(%(aiad_llm_prompt_tokens_total{model="gpt-forte"} 100\n),
                                         %(aiad_llm_completion_tokens_total{model="gpt-forte"} 50\n))
    end

    it 'computes the cost with the same rule as the UsageMeter' do
      esperado = UsageMeter.cost_of(prices, 'gpt-forte', 100, 50)

      expect(registry.render).to include(%(aiad_llm_cost_usd_total{model="gpt-forte"} #{esperado}\n))
    end
  end

  # A raiz inclui recuperação, compressão e montagem de prompt. Chamar aquilo
  # de "latência do modelo" seria culpar o modelo pelo tempo da busca.
  describe 'latência' do
    it 'measures the span that spent the tokens, not the whole trace' do
      exporter.export(trace_with([generation(duration: 2.0)], metadata: { model: 'gpt-forte' }))

      expect(registry.render).to include(%(aiad_llm_latency_seconds_sum{model="gpt-forte"} 2\n))
    end

    it 'records one observation per model call, so an agent with five calls counts five' do
      exporter.export(trace_with([generation, generation, generation], metadata: { model: 'gpt-forte' }))

      expect(registry.render).to include(%(aiad_llm_latency_seconds_count{model="gpt-forte"} 3\n))
    end
  end

  describe 'árvore de spans' do
    it 'finds a generation nested deeper than the first level' do
      aninhado = { name: 'react.turn', duration: 5.0, metadata: {}, usage: nil, spans: [generation] }
      exporter.export(trace_with([aninhado], metadata: { model: 'gpt-forte' }))

      expect(registry.render).to include(%(aiad_llm_calls_total{model="gpt-forte"} 1\n))
    end

    # O critério é ter gasto token, não se chamar `rag.generate`: renomear um
    # span não pode apagar a métrica.
    it 'does not depend on the span name' do
      renomeado = generation.merge(name: 'outro.nome.qualquer')
      exporter.export(trace_with([renomeado], metadata: { model: 'gpt-forte' }))

      expect(registry.render).to include(%(aiad_llm_calls_total{model="gpt-forte"} 1\n))
    end

    it 'lets a span declare a model of its own, for a router that changes model mid-trace' do
      exporter.export(trace_with([generation(metadata: { model: 'gpt-barato' })], metadata: { model: 'gpt-forte' }))

      expect(registry.render).to include(%(aiad_llm_calls_total{model="gpt-barato"} 1\n))
    end
  end

  # Contar isso como chamada afundaria o custo médio e mentiria sobre quantas
  # vezes o modelo foi acionado.
  describe 'pergunta sem contexto' do
    it 'records no call when no token was spent' do
      exporter.export(trace_with([{ name: 'rag.retrieve', duration: 0.1, metadata: {}, usage: nil, spans: [] }]))

      expect(registry.render).not_to include('aiad_llm_calls_total{')
    end
  end

  describe 'modelo não declarado' do
    it 'labels the call instead of dropping it' do
      exporter.export(trace_with([generation]))

      expect(registry.render).to include(%(aiad_llm_calls_total{model="#{described_class::UNKNOWN_MODEL}"} 1\n))
    end

    it 'charges nothing for a model with no configured price' do
      exporter.export(trace_with([generation]))

      expect(registry.render).to include(%(aiad_llm_cost_usd_total{model="#{described_class::UNKNOWN_MODEL}"} 0\n))
    end
  end

  describe 'ligado ao tracer de verdade' do
    it 'records what a real traced call produced' do
      tracer = Tracer.new(exporter: exporter)
      tracer.trace('rag.answer', metadata: { model: 'gpt-forte' }) do |span|
        span.span('rag.generate') { |generation| generation.usage = { prompt_tokens: 10, completion_tokens: 5 } }
      end

      expect(registry.render).to include(%(aiad_llm_prompt_tokens_total{model="gpt-forte"} 10\n))
    end
  end
end
