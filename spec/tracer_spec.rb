# frozen_string_literal: true

require_relative '../lib/tracer'

RSpec.describe Tracer do
  let(:exporter) { CollectingExporter.new }

  # Relógio que anda um segundo a cada leitura, para a duração ser conferível.
  let(:ticks) { (0..50).to_a }
  let(:clock) { -> { ticks.shift.to_f } }

  subject(:tracer) { described_class.new(exporter: exporter, clock: clock, ids: -> { 'id-fixo' }) }

  describe 'wrapping a piece of work' do
    # Tracer que muda o valor de retorno é intrusivo: quem instrumenta teria de
    # reescrever o codigo em volta.
    it 'returns what the block returned' do
      expect(tracer.trace('pergunta') { 'resposta' }).to eq('resposta')
    end

    it 'exports the trace once the root closes' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.traces.size).to eq(1)
    end

    it 'names the trace' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:name]).to eq('pergunta')
    end

    it 'records the input it was given' do
      tracer.trace('pergunta', input: 'quantos dias de férias?') { 'resposta' }

      expect(exporter.last[:input]).to eq('quantos dias de férias?')
    end

    # Ter de escrever `span.output =` em todo span instrumentado seria ruído:
    # o valor que o bloco devolveu já é a saída na esmagadora maioria dos casos.
    it 'takes the block result as the output' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:output]).to eq('resposta')
    end

    it 'lets the span override the output' do
      tracer.trace('pergunta') { |span| span.output = 'outra coisa' }

      expect(exporter.last[:output]).to eq('outra coisa')
    end

    it 'marks a run that went fine' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:status]).to eq(:ok)
    end

    it 'gives the span an id' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:id]).to eq('id-fixo')
    end
  end

  describe 'measuring time' do
    it 'reports how long the work took' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:duration]).to eq(1.0)
    end

    it 'times each nested span on its own' do
      tracer.trace('pergunta') { |span| span.span('recuperar') { 'trechos' } }

      expect(exporter.last[:spans].first[:duration]).to eq(1.0)
    end
  end

  # Duração se mede com relógio monotônico; posição na linha do tempo, não. Um
  # exportador que só recebe duração não consegue dizer *quando* cada span
  # aconteceu, e desenha uma cascata alinhada à direita que mente sobre a
  # ordem. As duas leituras convivem: a monotônica mede, a de parede situa.
  describe 'placing the work on a timeline' do
    let(:wall) { Time.utc(2026, 8, 29, 12, 0, 0) }

    subject(:tracer) do
      described_class.new(exporter: exporter, clock: clock, ids: -> { 'id-fixo' }, now: -> { wall })
    end

    it 'stamps when the trace started' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:started_at]).to eq(wall)
    end

    it 'stamps each nested span too' do
      tracer.trace('pergunta') { |span| span.span('recuperar') { 'trechos' } }

      expect(exporter.last[:spans].first[:started_at]).to eq(wall)
    end

    # O relógio de parede é lido uma vez por span, no começo. Ler de novo no
    # fim para calcular duração é o erro que o relógio monotônico existe para
    # evitar: um ajuste de NTP no meio produziria duração negativa.
    it 'still measures duration with the monotonic clock' do
      tracer.trace('pergunta') { 'resposta' }

      expect(exporter.last[:duration]).to eq(1.0)
    end

    it 'defaults to real time when nobody injects a clock' do
      described_class.new(exporter: exporter).trace('pergunta') { 'resposta' }

      expect(exporter.last[:started_at]).to be_within(60).of(Time.now.utc)
    end
  end

  describe 'nesting' do
    it 'keeps a nested span inside the trace' do
      tracer.trace('pergunta') { |span| span.span('recuperar') { 'trechos' } }

      expect(exporter.last[:spans].map { |nested| nested[:name] }).to eq(['recuperar'])
    end

    it 'keeps the nested spans in the order they happened' do
      tracer.trace('pergunta') do |span|
        span.span('recuperar') { 'trechos' }
        span.span('gerar') { 'resposta' }
      end

      expect(exporter.last[:spans].map { |nested| nested[:name] }).to eq(%w[recuperar gerar])
    end

    it 'nests a span inside a nested span' do
      tracer.trace('cadeia') do |span|
        span.span('rag') { |rag| rag.span('buscar') { 'trechos' } }
      end

      expect(exporter.last[:spans].first[:spans].first[:name]).to eq('buscar')
    end

    # Trace parcial não explica nada, e exportar span a span multiplicaria as
    # chamadas de rede por algo que só faz sentido inteiro.
    it 'does not export anything until the root closes' do
      tracer.trace('pergunta') do |span|
        span.span('recuperar') { 'trechos' }
        expect(exporter.traces).to be_empty
      end
    end

    it 'returns the nested block result to the caller' do
      value = tracer.trace('pergunta') { |span| span.span('recuperar') { 'trechos' } }

      expect(value).to eq('trechos')
    end
  end

  describe 'what gets annotated on a span' do
    it 'records token usage' do
      tracer.trace('gerar') { |span| span.usage = { total_tokens: 90 } }

      expect(exporter.last[:usage]).to eq(total_tokens: 90)
    end

    it 'records metadata' do
      tracer.trace('pergunta', metadata: { sessao: 'sessao-1' }) { 'resposta' }

      expect(exporter.last[:metadata]).to eq(sessao: 'sessao-1')
    end

    it 'lets the span add metadata while it runs' do
      tracer.trace('pergunta') { |span| span.annotate(modelo: 'barato') }

      expect(exporter.last[:metadata]).to eq(modelo: 'barato')
    end
  end

  # Observabilidade não pode engolir falha: o trace registra e a exceção segue.
  describe 'when the work fails' do
    let(:boom) { -> { raise ArgumentError, 'faltou o termo' } }

    it 'lets the error through' do
      expect { tracer.trace('pergunta') { boom.call } }.to raise_error(ArgumentError, 'faltou o termo')
    end

    it 'still exports the trace' do
      suppress { tracer.trace('pergunta') { boom.call } }

      expect(exporter.traces.size).to eq(1)
    end

    it 'marks the span as failed' do
      suppress { tracer.trace('pergunta') { boom.call } }

      expect(exporter.last[:status]).to eq(:error)
    end

    it 'records what blew up' do
      suppress { tracer.trace('pergunta') { boom.call } }

      expect(exporter.last[:error]).to eq('ArgumentError: faltou o termo')
    end

    it 'marks the failing nested span and the root above it' do
      suppress { tracer.trace('pergunta') { |span| span.span('gerar') { boom.call } } }

      expect(exporter.last[:spans].first[:status]).to eq(:error)
      expect(exporter.last[:status]).to eq(:error)
    end
  end

  # Se o Langfuse estiver fora do ar, o trace se perde; a requisição, não.
  describe 'when the exporter fails' do
    let(:exporter) { CollectingExporter.new { raise 'langfuse fora do ar' } }

    it 'does not take the caller down with it' do
      expect(tracer.trace('pergunta') { 'resposta' }).to eq('resposta')
    end
  end

  describe 'without an exporter' do
    subject(:tracer) { described_class.new }

    it 'runs the work anyway' do
      expect(tracer.trace('pergunta') { 'resposta' }).to eq('resposta')
    end
  end

  def suppress
    yield
  rescue StandardError
    nil
  end
end
