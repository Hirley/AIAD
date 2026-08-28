# frozen_string_literal: true

require 'json'
require 'rack/test'
require 'stringio'

require_relative '../../lib/api/request_logger'

RSpec.describe Api::RequestLogger do
  include Rack::Test::Methods

  let(:logs) { StringIO.new }
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:clock) { [0.0, 0.25] }

  def app
    described_class.new(downstream, io: logs, clock: -> { clock.shift },
                                    now: -> { Time.utc(2026, 8, 28, 21, 0, 0) }, ids: -> { 'id-fixo' })
  end

  def logged
    logs.string.lines.map { |line| JSON.parse(line) }
  end

  describe 'a linha de log' do
    before { post '/ask' }

    it 'writes one JSON line per request' do
      expect(logs.string.lines.size).to eq(1)
    end

    it 'records the method, the path and the status' do
      expect(logged.last).to include('method' => 'POST', 'path' => '/ask', 'status' => 200)
    end

    it 'records the duration in milliseconds' do
      expect(logged.last['duration_ms']).to eq(250.0)
    end

    it 'timestamps in UTC and ISO 8601, which is what a collector sorts by' do
      expect(logged.last['ts']).to eq('2026-08-28T21:00:00Z')
    end
  end

  # O corpo de /documents é um documento inteiro e o de /ask é a pergunta do
  # usuário: nenhum dos dois tem por que ficar em disco de log.
  describe 'o que nunca entra no log' do
    it 'does not log the request body' do
      post '/documents', JSON.generate(content: 'segredo industrial', source: 'a.txt')

      expect(logs.string).not_to include('segredo industrial')
    end

    it 'does not log the credential' do
      post '/ask', '{}', 'HTTP_AUTHORIZATION' => 'Bearer chave-secreta'

      expect(logs.string).not_to include('chave-secreta')
    end
  end

  describe 'quem fez a requisição' do
    # O principal é posto no env pela autenticação, que roda por dentro deste
    # middleware: por isso ele é lido depois da chamada, e não antes.
    let(:downstream) do
      lambda do |env|
        env['aiad.principal'] = { name: 'leitor', scopes: [:read] }
        [200, {}, []]
      end
    end

    it 'logs the principal name, which is what answers "who did this"' do
      post '/ask'

      expect(logged.last['principal']).to eq('leitor')
    end

    it 'logs no principal when the request was not authenticated' do
      described_class.new(->(_env) { [401, {}, []] }, io: logs).call('REQUEST_METHOD' => 'GET',
                                                                     'PATH_INFO' => '/ask')

      expect(logged.last['principal']).to be_nil
    end
  end

  describe 'id de requisição' do
    it 'generates one when the client did not send it' do
      get '/health'

      expect(logged.last['request_id']).to eq('id-fixo')
    end

    it 'returns it in the response, so the client can quote it in a ticket' do
      get '/health'

      expect(last_response.headers['x-request-id']).to eq('id-fixo')
    end

    it 'reuses the id the client sent, which is what links two services' do
      get '/health', {}, 'HTTP_X_REQUEST_ID' => 'do-cliente-123'

      expect(logged.last['request_id']).to eq('do-cliente-123')
    end

    # Uma quebra de linha nesse header viraria uma segunda linha de log
    # inteiramente forjada.
    it 'strips whatever could forge a second log line' do
      get '/health', {}, 'HTTP_X_REQUEST_ID' => %(abc"\n{"level":"info","status":200})

      expect(logs.string.lines.size).to eq(1)
    end

    it 'truncates an absurdly long id' do
      get '/health', {}, 'HTTP_X_REQUEST_ID' => 'a' * 500

      expect(logged.last['request_id'].size).to eq(described_class::MAX_ID_LENGTH)
    end
  end

  describe 'rota normalizada' do
    it 'logs the normalised route next to the raw path, so logs and metrics cross' do
      described_class.new(downstream, io: logs, route: ->(_path) { 'outra' })
                     .call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/inventada')

      expect(logged.last).to include('path' => '/inventada', 'route' => 'outra')
    end
  end

  describe 'quando o app estoura' do
    let(:downstream) { ->(_env) { raise IOError, 'falhou' } }

    it 'lets the exception through, because observing is not deciding' do
      expect { app.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ask') }.to raise_error(IOError)
    end

    it 'logs the failure at error level, with the class of the error' do
      begin
        app.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ask')
      rescue IOError
        nil
      end

      expect(logged.last).to include('level' => 'error', 'error' => 'IOError')
    end
  end
end
