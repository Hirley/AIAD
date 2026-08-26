# frozen_string_literal: true

require 'json'
require 'rack/test'

require_relative '../../lib/api/app'
require_relative '../../lib/api/authentication'
require_relative '../../lib/extractive_llm'
require_relative '../../lib/hybrid_retriever'
require_relative '../../spec/support/in_memory_qdrant_transport'

World(Rack::Test::Methods)

API_COLLECTION = 'documentos'
DOCUMENTO = 'A política de férias garante trinta dias por ano.'

def app
  @app
end

def json_response
  JSON.parse(last_response.body)
end

def post_json(path, payload, key)
  post path, JSON.generate(payload),
       { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{key}" }
end

Dado('que a API está no ar com as chaves:') do |table|
  configuration = table.hashes.map { |row| "#{row['nome']}:#{row['chave']}:#{row['escopos']}" }.join(';')

  lexical_index = Bm25Index.new
  etl = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
    embedder: EmbeddingGenerator.new(dimensions: 64),
    lexical_index: lexical_index
  )
  rag = RagPipeline.new(
    retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
    llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 2
  )

  @app = Api::Authentication.new(
    Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION),
    store: ApiKeyStore.parse(configuration)
  )
end

Quando('eu chamo {string} em {string} sem credencial') do |method, path|
  send(method.downcase.to_sym, path)
end

Quando('eu chamo {string} em {string} com a chave {string}') do |method, path, key|
  send(method.downcase.to_sym, path, {}, { 'HTTP_AUTHORIZATION' => "Bearer #{key}" })
end

Quando('eu ingiro um documento com a chave {string}') do |key|
  post_json('/documents', { content: DOCUMENTO, source: 'politica.txt' }, key)
end

Quando('eu pergunto {string} com a chave {string}') do |question, key|
  post_json('/ask', { question: question }, key)
end

Então('a resposta deve ter status {int}') do |status|
  expect(last_response.status).to eq(status)
end

Então('a resposta deve indicar o esquema {string}') do |scheme|
  expect(last_response.headers['www-authenticate']).to include(scheme)
end

Então('a resposta deve dizer que falta o escopo {string}') do |scope|
  expect(json_response['error']).to include(scope)
end

Então('a resposta da API deve citar a origem {string}') do |source|
  expect(json_response['sources']).to include(source)
end

Então('a resposta não deve conter o campo {string}') do |field|
  expect(json_response).not_to have_key(field)
end
