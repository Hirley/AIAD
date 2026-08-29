# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../lib/langfuse_exporter'

RSpec.describe LangfuseExporter do
  let(:transport) { FakeHttpClient.new(code: '207', body: JSON.generate(successes: [], errors: [])) }

  subject(:exporter) do
    described_class.new(public_key: 'pk-de-teste', secret_key: 'sk-de-teste',
                        client: transport, ids: -> { 'evento-fixo' })
  end

  # Um trace pronto, na forma exata que o Tracer entrega.
  def trace(overrides = {})
    { id: 'trace-1', name: 'pergunta', input: 'quantos dias de férias?', output: 'trinta dias',
      metadata: { sessao: 'sessao-1' }, usage: nil, status: :ok, error: nil,
      started_at: Time.utc(2026, 8, 29, 12, 0, 0), duration: 2.0, spans: [] }.merge(overrides)
  end

  def generation(overrides = {})
    trace({ id: 'span-1', name: 'rag.generate', input: 'prompt', output: 'trinta dias',
            metadata: { model: 'claude-sonnet-5' }, usage: { prompt_tokens: 90, completion_tokens: 10 },
            duration: 1.5, spans: [] }.merge(overrides))
  end

  def sent
    JSON.parse(transport.requests.last.body, symbolize_names: true)
  end

  def events_of(type)
    sent[:batch].select { |event| event[:type] == type }
  end

  describe 'o que sai na ingestão' do
    it 'sends the batch to the ingestion endpoint' do
      exporter.export(trace)

      expect(transport.requests.last.path).to eq(described_class::PATH)
    end

    it 'opens a trace for the root' do
      exporter.export(trace)

      expect(events_of('trace-create').first[:body]).to include(id: 'trace-1', name: 'pergunta')
    end

    # É o que a issue pede: ver prompt e resposta.
    it 'carries the question' do
      exporter.export(trace)

      expect(events_of('trace-create').first[:body][:input]).to eq('quantos dias de férias?')
    end

    it 'carries the answer' do
      exporter.export(trace)

      expect(events_of('trace-create').first[:body][:output]).to eq('trinta dias')
    end

    it 'carries the metadata, which is where the session id lives' do
      exporter.export(trace)

      expect(events_of('trace-create').first[:body][:metadata]).to eq(sessao: 'sessao-1')
    end
  end

  # O trace é o contêiner; a raiz é também trabalho que levou tempo. Emitir a
  # raiz como observação é o que faz a duração dela aparecer.
  describe 'as observações' do
    it 'emits an observation for the root as well' do
      exporter.export(trace)

      expect(events_of('span-create').map { |event| event[:body][:id] }).to eq(['trace-1'])
    end

    it 'emits one for each nested span' do
      exporter.export(trace(spans: [trace(id: 'span-1', name: 'recuperar', spans: [])]))

      expect(events_of('span-create').map { |event| event[:body][:name] }).to eq(%w[pergunta recuperar])
    end

    it 'hangs every observation on the same trace' do
      exporter.export(trace(spans: [trace(id: 'span-1', name: 'recuperar', spans: [])]))

      expect(events_of('span-create').map { |event| event[:body][:traceId] }).to all(eq('trace-1'))
    end

    it 'points a nested span at its parent' do
      exporter.export(trace(spans: [trace(id: 'span-1', name: 'recuperar', spans: [])]))

      expect(events_of('span-create').last[:body][:parentObservationId]).to eq('trace-1')
    end

    it 'leaves the root without a parent' do
      exporter.export(trace)

      expect(events_of('span-create').first[:body]).not_to have_key(:parentObservationId)
    end

    it 'keeps the nesting of a span inside a span' do
      nested = trace(id: 'neto', name: 'buscar', spans: [])
      exporter.export(trace(spans: [trace(id: 'filho', name: 'rag', spans: [nested])]))

      expect(events_of('span-create').last[:body][:parentObservationId]).to eq('filho')
    end
  end

  # Sem hora de parede não dá para desenhar a cascata: o relógio monotônico do
  # Tracer só faz sentido comparado consigo mesmo.
  describe 'a linha do tempo' do
    it 'says when the span started' do
      exporter.export(trace)

      expect(events_of('span-create').first[:body][:startTime]).to eq('2026-08-29T12:00:00.000Z')
    end

    it 'derives the end from the duration measured by the monotonic clock' do
      exporter.export(trace)

      expect(events_of('span-create').first[:body][:endTime]).to eq('2026-08-29T12:00:02.000Z')
    end

    it 'has no end time for a span that never closed' do
      exporter.export(trace(duration: nil))

      expect(events_of('span-create').first[:body]).not_to have_key(:endTime)
    end
  end

  # A distinção existe porque é ela que faz custo e tokens aparecerem no
  # painel do Langfuse. O critério é o mesmo do PrometheusTraceExporter --
  # ter `usage` --, de propósito: duas definições de "isto foi uma chamada de
  # modelo" divergiriam na primeira mudança.
  describe 'geração e span' do
    it 'reports a span that spent tokens as a generation' do
      exporter.export(trace(spans: [generation]))

      expect(events_of('generation-create').map { |event| event[:body][:name] }).to eq(['rag.generate'])
    end

    it 'reports a span that spent nothing as a plain span' do
      exporter.export(trace(spans: [generation(usage: nil)]))

      expect(events_of('generation-create')).to be_empty
    end

    # Pergunta que não recuperou nada não chama o modelo, e o uso vem zerado.
    it 'does not call a zero-token span a generation' do
      exporter.export(trace(spans: [generation(usage: { prompt_tokens: 0, completion_tokens: 0 })]))

      expect(events_of('generation-create')).to be_empty
    end

    it 'names the model that was billed' do
      exporter.export(trace(spans: [generation]))

      expect(events_of('generation-create').first[:body][:model]).to eq('claude-sonnet-5')
    end

    it 'reports the tokens spent on the prompt' do
      exporter.export(trace(spans: [generation]))

      expect(events_of('generation-create').first[:body][:usage]).to include(input: 90, output: 10)
    end
  end

  # Trace de requisição que falhou é justamente o que se vai olhar depois.
  describe 'quando o trabalho falhou' do
    let(:failed) { trace(status: :error, error: 'ArgumentError: faltou o termo') }

    it 'marks the observation as an error' do
      exporter.export(failed)

      expect(events_of('span-create').first[:body][:level]).to eq('ERROR')
    end

    it 'carries what blew up' do
      exporter.export(failed)

      expect(events_of('span-create').first[:body][:statusMessage]).to eq('ArgumentError: faltou o termo')
    end

    it 'says nothing about level when it went fine' do
      exporter.export(trace)

      expect(events_of('span-create').first[:body]).not_to have_key(:statusMessage)
    end
  end

  describe 'autenticação' do
    it 'authenticates with the key pair' do
      exporter.export(trace)

      expect(transport.requests.last['authorization'])
        .to eq("Basic #{['pk-de-teste:sk-de-teste'].pack('m0')}")
    end

    it 'declares the body as JSON' do
      exporter.export(trace)

      expect(transport.requests.last['content-type']).to eq('application/json')
    end
  end

  describe 'quando o Langfuse recusa' do
    it 'raises with the status' do
      transport.code = '401'
      transport.body = JSON.generate(message: 'chave inválida')

      expect { exporter.export(trace) }.to raise_error(described_class::Error, /401/)
    end

    # 207 é o sucesso normal desta rota: ela aceita o lote e relata item a item.
    it 'accepts the multi-status the ingestion route answers with' do
      expect { exporter.export(trace) }.not_to raise_error
    end

    it 'wraps a network failure instead of leaking a socket error' do
      allow(transport).to receive(:request).and_raise(Errno::ECONNREFUSED)

      expect { exporter.export(trace) }.to raise_error(described_class::Error, /falha de rede/)
    end
  end

  describe '.from_env' do
    let(:keys) { { 'LANGFUSE_PUBLIC_KEY' => 'pk', 'LANGFUSE_SECRET_KEY' => 'sk' } }

    it 'builds the exporter when both keys are there' do
      expect(described_class.from_env(keys)).to be_a(described_class)
    end

    # Sem as duas não há como autenticar, e um exportador pela metade só
    # falharia na primeira requisição, longe da causa.
    it 'returns nil without the secret key' do
      expect(described_class.from_env('LANGFUSE_PUBLIC_KEY' => 'pk')).to be_nil
    end

    it 'returns nil without the public key' do
      expect(described_class.from_env('LANGFUSE_SECRET_KEY' => 'sk')).to be_nil
    end

    it 'treats a blank key as no key' do
      expect(described_class.from_env(keys.merge('LANGFUSE_SECRET_KEY' => '  '))).to be_nil
    end

    it 'reads the host from the environment, for self-hosted instances' do
      expect(described_class.from_env(keys.merge('LANGFUSE_URL' => 'http://langfuse:3000')).url)
        .to eq('http://langfuse:3000')
    end

    it 'defaults to the hosted service' do
      expect(described_class.from_env(keys).url).to eq(described_class::DEFAULT_URL)
    end
  end

  # Mesma proteção do ApiKeyStore e do AnthropicLlm: um dump de exceção não
  # pode carregar credencial.
  describe 'a chave não vaza' do
    it 'keeps the secret out of inspect' do
      expect(exporter.inspect).not_to include('sk-de-teste')
    end

    it 'still says where it is sending, which is what one wants to see' do
      expect(exporter.inspect).to include(described_class::DEFAULT_URL)
    end
  end
end
