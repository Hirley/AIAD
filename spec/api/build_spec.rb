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

  # A partida não pode depender de o acervo estar de pé, e a métrica em zero é
  # o sinal de que o índice não carregou — o que separa "acervo vazio" de
  # "degradei para só o braço vetorial".
  describe 'aquecimento do índice léxico' do
    # Porta fechada, e não o `qdrant:6333` do grupo de fora. O contêiner da
    # suíte está na mesma rede do compose, então com a stack local no ar este
    # exemplo alcançava o Qdrant **de verdade** e media quantos documentos
    # estivessem lá — passava na máquina de quem tinha três, e mediria outra
    # coisa no CI. Teste cujo resultado depende do que está rodando ao lado não
    # é teste.
    let(:environment) { super().merge('QDRANT_URL' => 'http://127.0.0.1:1') }

    it 'builds even with Qdrant unreachable' do
      expect(app).to respond_to(:call)
    end

    it 'publishes the index size so the degradation is visible' do
      registry = Api::Observability.registry
      Api.build(env: environment, registry: registry, logs: logs)

      expect(registry.render).to include('aiad_lexical_index_documents 0')
    end
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
      requisicao = logs.string.lines.map { |linha| JSON.parse(linha) }.find { |linha| linha.key?('path') }

      expect(requisicao).to include('path' => '/health', 'status' => 200)
    end

    # A linha da partida sai antes de qualquer requisição, no mesmo stream e no
    # mesmo formato JSON. É o que faz quem sobe o contêiner descobrir com que
    # índice a API subiu sem ir raspar o `/metrics` de propósito — e ninguém
    # olha painel durante um boot.
    #
    # O que se cobra é a **forma** da linha, e não a contagem. A versão antiga
    # esperava `documents 0`, e isso só era verdade com o Qdrant vazio ou fora
    # do ar: este exemplo não substitui o transporte, então o aquecimento fala
    # com o Qdrant de verdade da rede do compose. Passava no CI, onde não há
    # Qdrant, e quebrava na máquina de quem tivesse a stack de pé com acervo.
    # Exemplo cujo resultado um serviço externo decide não mede o que diz medir.
    it 'writes a boot line for the lexical index warmup, in the same stream' do
      app

      expect(JSON.parse(logs.string.lines.first))
        .to include('event' => 'lexical_index_warmup')
        .and include('documents', 'complete', 'reason')
    end

    # Custo zero num painel lê-se como "saiu de graça", não como "ninguém
    # configurou preço" — e antes disto não havia por onde configurar. A linha
    # de partida é o que impede o zero de se passar pelo outro.
    def linha_de_preco
      app
      logs.string.lines.map { |linha| JSON.parse(linha) }.find { |linha| linha['event'] == 'model_prices' }
    end

    it 'warns at boot when there is a real model and no price table' do
      environment['ANTHROPIC_API_KEY'] = 'chave-de-modelo'

      expect(linha_de_preco).to include('level' => 'warn', 'models' => [])
    end

    it 'says which models have a price when there is one' do
      environment['ANTHROPIC_API_KEY'] = 'chave-de-modelo'
      environment['AIAD_MODEL_PRICES'] = 'claude-sonnet-5:3:15'

      expect(linha_de_preco).to include('level' => 'info', 'models' => ['claude-sonnet-5'])
    end

    # Sem modelo de verdade o custo é zero porque não houve custo, e avisar
    # disso seria ruído em toda partida de quem roda a stack extrativa — que é
    # o padrão do projeto.
    it 'stays quiet about prices when there is no real model to charge' do
      expect(linha_de_preco).to be_nil
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
