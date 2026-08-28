# frozen_string_literal: true

require 'tempfile'

require_relative '../lib/metric_registry'
require_relative '../lib/process_collector'

RSpec.describe ProcessCollector do
  let(:registry) { MetricRegistry.new }
  let(:status) do
    file = Tempfile.new('status')
    file.write("Name:\truby\nVmRSS:\t  262144 kB\nThreads:\t5\n")
    file.close
    file
  end

  after { status.unlink }

  subject(:collector) do
    described_class.new(status_path: status.path, cpu: -> { 1.5 }, clock: -> { 100.0 }, threads: -> { 5 })
  end

  describe '#resident_memory_bytes' do
    it 'reads the resident memory and converts kB to bytes' do
      expect(collector.resident_memory_bytes).to eq(262_144 * 1024)
    end

    # A imagem é Linux, mas a suíte roda onde o desenvolvedor estiver.
    it 'returns nil where there is no /proc to read' do
      expect(described_class.new(status_path: '/nao/existe').resident_memory_bytes).to be_nil
    end
  end

  describe '#install' do
    before { collector.install(registry) }

    it 'publishes the resident memory in bytes' do
      expect(registry.render).to include("aiad_process_resident_memory_bytes 268435456\n")
    end

    it 'publishes the accumulated CPU time in seconds' do
      expect(registry.render).to include("aiad_process_cpu_seconds_total 1.5\n")
    end

    it 'publishes the CPU as a counter, because it only goes up' do
      expect(registry.render).to include("# TYPE aiad_process_cpu_seconds_total counter\n")
    end

    it 'publishes the live thread count' do
      expect(registry.render).to include("aiad_process_threads 5\n")
    end

    # Métrica ausente é melhor que métrica mentindo: zero aqui diria "processo
    # leve" onde a verdade é "não sei medir".
    it 'declares no memory metric where it cannot be measured' do
      elsewhere = MetricRegistry.new
      described_class.new(status_path: '/nao/existe').install(elsewhere)

      expect(elsewhere.render).not_to include('aiad_process_resident_memory_bytes')
    end
  end

  describe 'uptime' do
    it 'counts from the moment the collector was built' do
      # A primeira leitura é a da construção; a segunda é a da pergunta.
      tempo = [10.0, 42.0]
      collector = described_class.new(status_path: status.path, clock: -> { tempo.shift })

      expect(collector.uptime).to eq(32.0)
    end
  end

  # O valor lido tem de ser o do scrape, não o da subida do processo: memória
  # congelada no boot é a métrica mais inútil possível.
  describe 'amostragem' do
    it 'reads the value again on each render' do
      leituras = [1.0, 2.0]
      described_class.new(status_path: status.path, cpu: -> { leituras.shift }).install(registry)

      expect(registry.render).to include("aiad_process_cpu_seconds_total 1\n")
      expect(registry.render).to include("aiad_process_cpu_seconds_total 2\n")
    end
  end
end
