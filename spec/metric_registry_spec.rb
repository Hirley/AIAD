# frozen_string_literal: true

require_relative '../lib/metric_registry'

RSpec.describe MetricRegistry do
  subject(:registry) { described_class.new }

  describe 'contador' do
    it 'renders the declared metric with help and type' do
      registry.counter('aiad_requisicoes_total', help: 'Requisições atendidas.')

      expect(registry.render).to include("# HELP aiad_requisicoes_total Requisições atendidas.\n",
                                         "# TYPE aiad_requisicoes_total counter\n")
    end

    # A diferença entre "zero" e "sem dados" é a diferença entre um serviço
    # parado e um serviço quieto.
    it 'starts an unlabelled counter at zero, before anything happened' do
      registry.counter('aiad_requisicoes_total', help: 'Requisições atendidas.')

      expect(registry.render).to include("aiad_requisicoes_total 0\n")
    end

    it 'counts' do
      registry.counter('aiad_requisicoes_total', help: 'Requisições.')
      2.times { registry.increment('aiad_requisicoes_total') }

      expect(registry.render).to include("aiad_requisicoes_total 2\n")
    end

    it 'counts each label combination on its own' do
      registry.counter('aiad_requisicoes_total', help: 'Requisições.', labels: %i[rota])
      registry.increment('aiad_requisicoes_total', labels: { rota: '/ask' })
      registry.increment('aiad_requisicoes_total', labels: { rota: '/ask' })
      registry.increment('aiad_requisicoes_total', labels: { rota: '/health' })

      expect(registry.render).to include(%(aiad_requisicoes_total{rota="/ask"} 2\n),
                                         %(aiad_requisicoes_total{rota="/health"} 1\n))
    end

    it 'does not invent a series for a labelled metric that was never touched' do
      registry.counter('aiad_requisicoes_total', help: 'Requisições.', labels: %i[rota])

      expect(registry.render).not_to include('aiad_requisicoes_total 0')
    end
  end

  describe 'medidor' do
    it 'keeps the last value set' do
      registry.gauge('aiad_conexoes', help: 'Conexões abertas.')
      registry.set('aiad_conexoes', 7)
      registry.set('aiad_conexoes', 3)

      expect(registry.render).to include("aiad_conexoes 3\n")
    end

    # Memória e CPU não se acumulam: o valor certo é o que o sistema diz na
    # hora da coleta.
    it 'samples a block at render time, not at declaration time' do
      leituras = [1, 2, 3]
      registry.gauge('aiad_memoria_bytes', help: 'Memória.') { leituras.shift }

      expect(registry.render).to include("aiad_memoria_bytes 1\n")
      expect(registry.render).to include("aiad_memoria_bytes 2\n")
    end

    it 'refuses labels on a sampled metric, which has nothing to label' do
      expect { registry.gauge('x', help: 'x', labels: %i[rota]) { 1 } }.to raise_error(ArgumentError)
    end
  end

  describe 'histograma' do
    before do
      registry.histogram('aiad_duracao_segundos', help: 'Duração.', labels: %i[rota], buckets: [0.1, 1])
    end

    it 'accumulates buckets, as the format requires' do
      registry.observe('aiad_duracao_segundos', 0.05, labels: { rota: '/ask' })

      expect(registry.render).to include(%(aiad_duracao_segundos_bucket{rota="/ask",le="0.1"} 1\n),
                                         %(aiad_duracao_segundos_bucket{rota="/ask",le="1"} 1\n))
    end

    it 'leaves a slow observation out of the fast buckets' do
      registry.observe('aiad_duracao_segundos', 2.0, labels: { rota: '/ask' })

      expect(registry.render).to include(%(aiad_duracao_segundos_bucket{rota="/ask",le="0.1"} 0\n),
                                         %(aiad_duracao_segundos_bucket{rota="/ask",le="1"} 0\n))
    end

    it 'counts every observation in the +Inf bucket' do
      registry.observe('aiad_duracao_segundos', 0.05, labels: { rota: '/ask' })
      registry.observe('aiad_duracao_segundos', 30.0, labels: { rota: '/ask' })

      expect(registry.render).to include(%(aiad_duracao_segundos_bucket{rota="/ask",le="+Inf"} 2\n))
    end

    it 'reports sum and count, which is what an average needs' do
      registry.observe('aiad_duracao_segundos', 0.5, labels: { rota: '/ask' })
      registry.observe('aiad_duracao_segundos', 1.5, labels: { rota: '/ask' })

      expect(registry.render).to include(%(aiad_duracao_segundos_sum{rota="/ask"} 2\n),
                                         %(aiad_duracao_segundos_count{rota="/ask"} 2\n))
    end
  end

  describe 'erros de declaração' do
    it 'refuses to touch a metric that was never declared' do
      expect { registry.increment('nao_declarada') }.to raise_error(described_class::UnknownMetricError)
    end

    it 'refuses the same name twice' do
      registry.counter('aiad_x', help: 'x')

      expect { registry.counter('aiad_x', help: 'x') }.to raise_error(described_class::DuplicateMetricError)
    end

    it 'refuses to observe a counter as if it were a histogram' do
      registry.counter('aiad_x', help: 'x')

      expect { registry.observe('aiad_x', 1) }.to raise_error(described_class::WrongTypeError)
    end

    # Rótulo digitado errado criaria uma série irmã em silêncio, e o painel
    # continuaria mostrando a série antiga parada no tempo.
    it 'refuses a label that was not declared' do
      registry.counter('aiad_x', help: 'x', labels: %i[rota])

      expect { registry.increment('aiad_x', labels: { rot: '/ask' }) }
        .to raise_error(described_class::UnknownLabelError)
    end

    it 'refuses a missing label' do
      registry.counter('aiad_x', help: 'x', labels: %i[rota status])

      expect { registry.increment('aiad_x', labels: { rota: '/ask' }) }
        .to raise_error(described_class::UnknownLabelError)
    end
  end

  describe 'formato' do
    # Dois scrapes seguidos precisam ser comparáveis com diff; ordem de Hash
    # não serve como contrato.
    it 'renders metrics in name order, whatever the declaration order' do
      registry.counter('aiad_z', help: 'z')
      registry.counter('aiad_a', help: 'a')

      expect(registry.render.index('aiad_a')).to be < registry.render.index('aiad_z')
    end

    it 'writes whole numbers without a decimal point' do
      registry.gauge('aiad_x', help: 'x')
      registry.set('aiad_x', 3)

      expect(registry.render).to include("aiad_x 3\n")
    end

    it 'keeps the fraction when there is one' do
      registry.gauge('aiad_x', help: 'x')
      registry.set('aiad_x', 0.5)

      expect(registry.render).to include("aiad_x 0.5\n")
    end

    it 'escapes quotes in label values, which would otherwise break the line' do
      registry.counter('aiad_x', help: 'x', labels: %i[rota])
      registry.increment('aiad_x', labels: { rota: 'a"b' })

      expect(registry.render).to include('rota="a\"b"')
    end

    it 'announces the content type the Prometheus expects' do
      expect(PrometheusExposition::CONTENT_TYPE).to include('text/plain', 'version=0.0.4')
    end
  end

  # Cinco threads do Puma incrementando o mesmo contador sem lock perdem
  # amostra justamente sob carga, que é quando a métrica importa.
  describe 'concorrência' do
    it 'does not lose increments across threads' do
      registry.counter('aiad_x', help: 'x')
      Array.new(5) { Thread.new { 200.times { registry.increment('aiad_x') } } }.each(&:join)

      expect(registry.render).to include("aiad_x 1000\n")
    end
  end
end
