# frozen_string_literal: true

require_relative '../lib/http_qdrant_transport'

RSpec.describe HttpQdrantTransport do
  let(:client) { FakeHttpClient.new }

  subject(:transport) { described_class.new(url: 'http://qdrant:6333', client: client) }

  def last_request
    client.requests.last
  end

  describe 'montagem da requisição' do
    it 'builds the full path from the base url' do
      transport.get('/collections/documentos')

      expect(last_request.path).to eq('/collections/documentos')
    end

    it 'sends the body as JSON with the right content type' do
      transport.put('/collections/documentos', vectors: { size: 384 })

      expect(last_request.body).to eq('{"vectors":{"size":384}}')
      expect(last_request['content-type']).to eq('application/json')
    end

    it 'uses the right HTTP verb for each method' do
      transport.get('/a')
      transport.put('/a', {})
      transport.post('/a', {})
      transport.patch('/a', {})
      transport.delete('/a')

      expect(client.requests.map(&:method)).to eq(%w[GET PUT POST PATCH DELETE])
    end

    it 'sends no body on get and delete' do
      transport.get('/a')
      transport.delete('/a')

      expect(client.requests.map(&:body)).to all(be_nil)
    end

    it 'sends the api key header when configured' do
      described_class.new(url: 'http://qdrant:6333', api_key: 'segredo', client: client).get('/a')

      expect(last_request['api-key']).to eq('segredo')
    end

    it 'omits the api key header when not configured' do
      transport.get('/a')

      expect(last_request['api-key']).to be_nil
    end
  end

  describe 'tratamento da resposta' do
    it 'parses a successful response with symbol keys and marks it ok' do
      expect(transport.get('/a')).to eq(ok: true, result: { status: 'ok' })
    end

    it 'reports failure without raising when the status is not 2xx' do
      failing = described_class.new(url: 'http://qdrant:6333',
                                    client: FakeHttpClient.new(code: '404', body: '{"status":{"error":"not found"}}'))

      result = failing.get('/collections/inexistente')

      expect(result[:ok]).to be(false)
      expect(result[:status]).to eq(404)
    end

    it 'handles an empty body' do
      empty = described_class.new(url: 'http://qdrant:6333', client: FakeHttpClient.new(body: ''))

      expect(empty.get('/a')).to eq(ok: true)
    end

    it 'handles a body that is not valid JSON' do
      broken = described_class.new(url: 'http://qdrant:6333', client: FakeHttpClient.new(body: 'nao e json'))

      expect(broken.get('/a')).to include(ok: false)
    end
  end

  describe '.from_env' do
    it 'reads the url and the api key from the environment' do
      transport = described_class.from_env({ 'QDRANT_URL' => 'http://outro:1234', 'QDRANT_API_KEY' => 'k' })

      expect(transport.url).to eq('http://outro:1234')
    end

    it 'falls back to localhost when the environment is empty' do
      expect(described_class.from_env({}).url).to eq(described_class::DEFAULT_URL)
    end
  end
end
