# frozen_string_literal: true

require 'rack/test'
require 'stringio'

require_relative '../../lib/api/build'

RSpec.describe 'Api.build' do
  include Rack::Test::Methods

  let(:environment) do
    { 'QDRANT_URL' => 'http://qdrant:6333',
      'AIAD_API_KEYS' => 'robo:chave-total:read,write;prometheus:chave-metricas:metrics' }
  end
  # O log estruturado vai para um StringIO na suíte: em produção ele vai para a
  # saída padrão, que é onde o coletor lê.
  let(:logs) { StringIO.new }

  def app
    Api.build(env: environment, logs: logs)
  end

  it 'builds a rack application' do
    expect(app).to respond_to(:call)
  end

  it 'answers the health check without touching Qdrant or requiring a key' do
    get '/health'

    expect(last_response.status).to eq(200)
  end

  # A montagem inteira, do jeito que o `config.ru` a usa: se a página não vier
  # na imagem, o `Api.build` nem chega a devolver uma aplicação.
  it 'serves the console page at the root without requiring a key' do
    get '/'

    expect(last_response.status).to eq(200)
    expect(last_response.headers['content-type']).to include('text/html')
  end

  it 'protects the other routes with the configured keys' do
    post '/search'

    expect(last_response.status).to eq(401)
  end

  it 'accepts the configured key' do
    post '/documents', JSON.generate(content: '', source: ''),
         { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer chave-total' }

    # 422 (e não 401/403) prova que a credencial passou pelo controle de acesso.
    expect(last_response.status).to eq(422)
  end

  describe 'observabilidade' do
    def scrape
      get '/metrics', {}, 'HTTP_AUTHORIZATION' => 'Bearer chave-metricas'
    end

    it 'exposes the metrics to a key with the metrics scope' do
      scrape

      expect(last_response.status).to eq(200)
    end

    it 'does not expose the metrics to whoever has no key' do
      get '/metrics'

      expect(last_response.status).to eq(401)
    end

    # Quem lê documentos não precisa ver latência, rota e status da operação.
    it 'does not expose the metrics to a key that only reads documents' do
      get '/metrics', {}, 'HTTP_AUTHORIZATION' => 'Bearer chave-total'

      expect(last_response.status).to eq(403)
    end

    it 'publishes the process metrics from the first scrape' do
      scrape

      expect(last_response.body).to include('aiad_process_cpu_seconds_total')
    end

    it 'counts the requests it served' do
      get '/health'
      scrape

      expect(last_response.body).to include(%(route="/health",status="200"))
    end

    # Métrica e log ficam por fora da autenticação de propósito: um pico de 401
    # é o que se quer ver, e não dá para vê-lo se a requisição morre antes de
    # ser contada.
    it 'counts a rejected request too' do
      post '/search'
      scrape

      expect(last_response.body).to include(%(status="401"))
    end

    it 'writes one structured log line per request' do
      get '/health'

      expect(JSON.parse(logs.string.lines.first)).to include('path' => '/health', 'status' => 200)
    end

    it 'answers with the request id, so a log line can be found from a ticket' do
      get '/health'

      expect(last_response.headers['x-request-id']).not_to be_empty
    end
  end

  it 'uses the collection given in the environment' do
    expect(Api.collection_for(environment.merge('AIAD_COLLECTION' => 'contratos'))).to eq('contratos')
  end

  it 'falls back to the default collection' do
    expect(Api.collection_for(environment)).to eq(Api::DEFAULT_COLLECTION)
  end

  describe '.retrieval_options' do
    it 'turns reranking and semantic cache on by default' do
      expect(Api.retrieval_options({})).to include(rerank: true, cache: true)
    end

    it 'leaves HyDE and parent documents off by default, since both cost more' do
      expect(Api.retrieval_options({})).to include(hyde: false, parent_documents: false)
    end

    it 'reads the flags from the environment' do
      options = Api.retrieval_options('AIAD_HYDE' => '1', 'AIAD_RERANK' => 'false')

      expect(options).to include(hyde: true, rerank: false)
    end

    it 'accepts the usual ways of writing a flag' do
      expect(Api.retrieval_options('AIAD_HYDE' => 'true')[:hyde]).to be(true)
      expect(Api.retrieval_options('AIAD_HYDE' => 'sim')[:hyde]).to be(false)
    end

    it 'reads the context budget' do
      expect(Api.retrieval_options('AIAD_CONTEXT_BUDGET' => '900')[:context_budget]).to eq(900)
    end

    it 'has a default context budget' do
      expect(Api.retrieval_options({})[:context_budget]).to eq(Api::DEFAULT_CONTEXT_BUDGET)
    end
  end
end
