# frozen_string_literal: true

require 'rack/test'

require_relative '../../lib/api/build'

RSpec.describe 'Api.build' do
  include Rack::Test::Methods

  let(:environment) do
    { 'QDRANT_URL' => 'http://qdrant:6333', 'AIAD_API_KEYS' => 'robo:chave-total:read,write' }
  end

  def app
    Api.build(env: environment)
  end

  it 'builds a rack application' do
    expect(app).to respond_to(:call)
  end

  it 'answers the health check without touching Qdrant or requiring a key' do
    get '/health'

    expect(last_response.status).to eq(200)
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
