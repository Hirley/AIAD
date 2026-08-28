# frozen_string_literal: true

require 'rack/test'

require_relative '../../lib/api/authentication'

RSpec.describe Api::Authentication do
  include Rack::Test::Methods

  let(:store) { ApiKeyStore.parse('leitor:chave-leitura:read;robo:chave-total:read,write') }
  let(:downstream) do
    ->(env) { [200, { 'content-type' => 'text/plain' }, [env['aiad.principal'].to_h[:name].to_s]] }
  end

  def app
    described_class.new(downstream, store: store)
  end

  def json_body
    JSON.parse(last_response.body)
  end

  describe 'rota pública' do
    it 'lets the health check through without a key' do
      get '/health'

      expect(last_response.status).to eq(200)
    end
  end

  describe 'sem credencial' do
    it 'answers 401 when there is no Authorization header' do
      post '/search'

      expect(last_response.status).to eq(401)
    end

    it 'tells the client which scheme to use' do
      post '/search'

      expect(last_response.headers['www-authenticate']).to include('Bearer')
    end

    it 'answers 401 when the scheme is not Bearer' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Basic chave-leitura' }

      expect(last_response.status).to eq(401)
    end

    it 'answers 401 for an unknown key' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-errada' }

      expect(last_response.status).to eq(401)
    end

    it 'does not echo the rejected key' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-errada' }

      expect(last_response.body).not_to include('chave-errada')
    end

    it 'answers JSON' do
      post '/search'

      expect(json_body).to include('error')
    end
  end

  describe 'escopo insuficiente' do
    it 'answers 403 when the key cannot write' do
      post '/documents', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-leitura' }

      expect(last_response.status).to eq(403)
    end

    it 'says which scope is missing' do
      post '/documents', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-leitura' }

      expect(json_body['error']).to include('write')
    end

    # Um 403 é justamente o caso em que se quer saber quem foi recusado: a
    # credencial era válida. Por isso o principal entra no env antes da
    # checagem de escopo, e o log estruturado consegue nomeá-lo.
    it 'records who was refused, so the log can name them' do
      environment = { 'REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/documents',
                      'HTTP_AUTHORIZATION' => 'Bearer chave-leitura' }
      status, = described_class.new(downstream, store: store).call(environment)

      expect(status).to eq(403)
      expect(environment['aiad.principal']).to include(name: 'leitor')
    end
  end

  describe 'credencial válida' do
    it 'lets a read key search' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-leitura' }

      expect(last_response.status).to eq(200)
    end

    it 'lets a write key ingest' do
      post '/documents', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-total' }

      expect(last_response.status).to eq(200)
    end

    it 'passes the authenticated principal downstream' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Bearer chave-leitura' }

      expect(last_response.body).to eq('leitor')
    end
  end

  describe 'store vazio' do
    let(:store) { ApiKeyStore.parse(nil) }

    it 'refuses every protected request instead of letting everyone in' do
      post '/search', {}, { 'HTTP_AUTHORIZATION' => 'Bearer qualquer' }

      expect(last_response.status).to eq(401)
    end
  end
end
