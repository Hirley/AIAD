# frozen_string_literal: true

require 'rack/test'

require_relative '../../lib/api/app'

RSpec.describe Api::App do
  include Rack::Test::Methods

  let(:transport) { InMemoryQdrantTransport.new }
  let(:lexical_index) { Bm25Index.new }
  let(:etl) do
    EtlPipeline.new(qdrant: QdrantClient.new(transport: transport),
                    embedder: EmbeddingGenerator.new(dimensions: 64),
                    lexical_index: lexical_index)
  end
  let(:llm) { FakeLlm.new }
  let(:rag) { RagPipeline.new(retriever: etl, llm: llm, collection: 'documentos', top_k: 2) }

  def app
    described_class.new(etl: etl, rag: rag, collection: 'documentos')
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def post_json(path, payload)
    post path, JSON.generate(payload), { 'CONTENT_TYPE' => 'application/json' }
  end

  def ingest_sample
    post_json('/documents', content: 'A política de férias garante trinta dias por ano.', source: 'politica.txt')
  end

  describe 'GET /health' do
    it 'answers ok' do
      get '/health'

      expect(last_response.status).to eq(200)
      expect(json_body['status']).to eq('ok')
    end
  end

  describe 'POST /documents' do
    it 'ingests the document and answers 201' do
      ingest_sample

      expect(last_response.status).to eq(201)
      expect(json_body['chunks']).to be > 0
    end

    it 'reports the source and the generated point ids' do
      ingest_sample

      expect(json_body['source']).to eq('politica.txt')
      expect(json_body['point_ids'].size).to eq(json_body['chunks'])
    end

    it 'accepts the format and the metadata' do
      post_json('/documents', content: '2026-08-26T10:00:00Z ERROR Falha no banco', source: 'app.log',
                              format: 'log', metadata: { autor: 'infra' })

      expect(last_response.status).to eq(201)
    end

    it 'answers 422 when content is missing' do
      post_json('/documents', source: 'politica.txt')

      expect(last_response.status).to eq(422)
      expect(json_body['error']).to include('content')
    end

    it 'answers 422 when source is missing' do
      post_json('/documents', content: 'texto')

      expect(last_response.status).to eq(422)
    end

    it 'answers 422 for blank content instead of leaking the internal error' do
      post_json('/documents', content: '   ', source: 'vazio.txt')

      expect(last_response.status).to eq(422)
    end

    it 'answers 422 for an unsupported format' do
      post_json('/documents', content: 'texto', source: 's.txt', format: 'planilha')

      expect(last_response.status).to eq(422)
    end

    it 'answers 400 for a malformed body' do
      post '/documents', 'isto nao e json', { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
    end
  end

  describe 'POST /search' do
    before { ingest_sample }

    it 'returns the matching passages' do
      post_json('/search', query: 'férias')

      expect(last_response.status).to eq(200)
      expect(json_body['results'].first['source']).to eq('politica.txt')
    end

    it 'returns the text and the score of each result' do
      post_json('/search', query: 'férias')

      expect(json_body['results'].first).to include('text', 'score')
    end

    it 'respects the limit' do
      post_json('/search', query: 'férias', limit: 1)

      expect(json_body['results'].size).to eq(1)
    end

    it 'answers 422 without a query' do
      post_json('/search', {})

      expect(last_response.status).to eq(422)
    end
  end

  describe 'POST /ask' do
    before { ingest_sample }

    it 'answers the question with the generated answer and the sources' do
      post_json('/ask', question: 'quantos dias de férias por ano')

      expect(last_response.status).to eq(200)
      expect(json_body['answer']).to eq('Trinta dias por ano [1].')
      expect(json_body['sources']).to include('politica.txt')
    end

    it 'returns the passages that grounded the answer' do
      post_json('/ask', question: 'quantos dias de férias por ano')

      expect(json_body['passages'].first).to include('source', 'score')
    end

    it 'does not return the prompt sent to the model' do
      post_json('/ask', question: 'quantos dias de férias por ano')

      expect(json_body).not_to have_key('prompt')
    end

    it 'answers 422 without a question' do
      post_json('/ask', {})

      expect(last_response.status).to eq(422)
    end
  end

  describe 'rota inexistente' do
    it 'answers 404 in JSON' do
      get '/nao-existe'

      expect(last_response.status).to eq(404)
      expect(json_body).to include('error')
    end
  end

  describe 'quando o Qdrant está indisponível' do
    let(:transport) { FailingQdrantTransport.new }

    it 'answers 503 on search instead of a generic internal error' do
      post_json('/search', query: 'férias')

      expect(last_response.status).to eq(503)
    end

    it 'answers 503 on ingestion' do
      ingest_sample

      expect(last_response.status).to eq(503)
    end

    it 'answers 503 when asking' do
      post_json('/ask', question: 'quantos dias?')

      expect(last_response.status).to eq(503)
    end

    it 'does not leak the internal path or the exception class' do
      post_json('/search', query: 'férias')

      expect(last_response.body).not_to include('QdrantClient')
      expect(last_response.body).not_to include('/collections/')
    end

    it 'explains that the dependency is unavailable' do
      post_json('/search', query: 'férias')

      expect(json_body['error']).to include('indisponível')
    end
  end

  describe 'custo na resposta de POST /ask' do
    before { ingest_sample }

    it 'reports the tokens spent' do
      post_json('/ask', question: 'quantos dias de férias por ano')

      expect(json_body['usage']).to include('prompt_tokens', 'completion_tokens', 'total_tokens')
    end

    it 'says whether the answer came from the cache' do
      post_json('/ask', question: 'quantos dias de férias por ano')

      expect(json_body['cached']).to be(false)
    end
  end
end
