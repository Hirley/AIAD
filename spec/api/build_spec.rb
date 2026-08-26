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
end
