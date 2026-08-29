# frozen_string_literal: true

require_relative '../../lib/api/console'

# Monta a pilha **com o console dentro da autenticação**, que é a composição
# que vai para produção. Os passos de `api_steps.rb` montam sem ele de
# propósito: lá o assunto é o controle de acesso, e um middleware a mais só
# tornaria a causa da falha menos óbvia.
Dado('que o console está no ar com as chaves:') do |table|
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
    Api::Console.new(Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION)),
    store: ApiKeyStore.parse(configuration)
  )
end

Então('a página servida deve ser HTML') do
  expect(last_response.headers['content-type']).to include('text/html')
  expect(last_response.body).to include('<!doctype html>')
end

Então('a página servida não deve conter a chave {string}') do |key|
  expect(last_response.body).not_to include(key)
end

Então('a página servida deve ter um campo de senha para a chave') do
  expect(last_response.body).to include('type="password"')
end
