# frozen_string_literal: true

require_relative '../lib/composite_exporter'

RSpec.describe CompositeExporter do
  let(:prometheus) { CollectingExporter.new }
  let(:langfuse) { CollectingExporter.new }
  let(:trace) { { id: 'trace-1', name: 'pergunta' } }

  subject(:exporter) { described_class.new([prometheus, langfuse]) }

  describe 'fanning the trace out' do
    it 'gives the trace to the first exporter' do
      exporter.export(trace)

      expect(prometheus.last).to eq(trace)
    end

    it 'gives the same trace to the second one' do
      exporter.export(trace)

      expect(langfuse.last).to eq(trace)
    end
  end

  # O caso que motiva a classe: o Langfuse é serviço externo e cai; o registro
  # de métricas é memória do processo e não cai. Se a queda de um impedisse o
  # outro de receber, um serviço fora do ar levaria junto a métrica que se usa
  # justamente para descobrir que algo está fora do ar.
  describe 'when one of them fails' do
    let(:langfuse) { CollectingExporter.new { raise 'langfuse fora do ar' } }

    subject(:exporter) { described_class.new([langfuse, prometheus]) }

    it 'still delivers to the healthy one, even though it comes after' do
      suppress { exporter.export(trace) }

      expect(prometheus.last).to eq(trace)
    end

    # Engolir aqui também esconderia chave errada: quem chama em produção é o
    # Tracer, e é ele que decide não derrubar a requisição por causa disso.
    it 'lets the failure through once everyone has been served' do
      expect { exporter.export(trace) }.to raise_error(/langfuse fora do ar/)
    end

    it 'reports the first failure when more than one breaks' do
      outro = CollectingExporter.new { raise 'prometheus quebrado' }

      expect { described_class.new([langfuse, outro]).export(trace) }
        .to raise_error(/langfuse fora do ar/)
    end
  end

  # Montar um composto para envolver um exportador só seria uma camada que não
  # decide nada, e apareceria em todo backtrace daqui para frente.
  describe '.for' do
    it 'returns the exporter itself when there is only one' do
      expect(described_class.for(prometheus)).to be(prometheus)
    end

    it 'composes when there is more than one' do
      expect(described_class.for(prometheus, langfuse)).to be_a(described_class)
    end

    # É o caso normal: sem chave do Langfuse, sobra só o Prometheus.
    it 'ignores the ones that were not configured' do
      expect(described_class.for(prometheus, nil)).to be(prometheus)
    end

    it 'returns nil when nothing was configured' do
      expect(described_class.for(nil, nil)).to be_nil
    end
  end

  def suppress
    yield
  rescue StandardError
    nil
  end
end
