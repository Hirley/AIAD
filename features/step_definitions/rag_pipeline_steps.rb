# frozen_string_literal: true

require_relative '../../lib/etl_pipeline'
require_relative '../../lib/rag_pipeline'
require_relative '../../spec/support/fake_llm'
require_relative '../../spec/support/in_memory_qdrant_transport'

RAG_COLLECTION = 'documentos'

def autor_filter(autor)
  { must: [{ key: 'autor', match: { value: autor } }] }
end

Dado('que o assistente indexou os documentos:') do |table|
  embedder = EmbeddingGenerator.new(dimensions: 64)
  etl = EtlPipeline.new(qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new), embedder: embedder)

  table.hashes.each do |row|
    etl.run(row['conteudo'], collection: RAG_COLLECTION, source: row['origem'], metadata: { autor: row['autor'] })
  end

  @llm = FakeLlm.new
  @rag = RagPipeline.new(retriever: etl, llm: @llm, collection: RAG_COLLECTION, top_k: 1)
end

Quando('eu pergunto {string}') do |question|
  @result = @rag.answer(question)
end

Quando('eu pergunto {string} filtrando pelo autor {string}') do |question, autor|
  @result = @rag.answer(question, filter: autor_filter(autor))
end

Então('o contexto enviado ao modelo deve conter o trecho de {string}') do |source|
  passage = @result[:passages].find { |candidate| candidate[:source] == source }

  expect(passage).not_to be_nil
  expect(@llm.prompts.last).to include(passage[:text])
end

Então('a resposta deve citar a origem {string}') do |source|
  expect(@result[:sources]).to include(source)
end

Então('a resposta não deve citar a origem {string}') do |source|
  expect(@result[:sources]).not_to include(source)
end

Então('o prompt deve instruir o modelo a responder apenas com o contexto') do
  expect(@llm.prompts.last).to include('usando apenas os trechos de contexto')
end

Então('o modelo não deve ter sido chamado') do
  expect(@llm.prompts).to be_empty
end

Então('a resposta deve informar que a informação não foi encontrada') do
  expect(@result[:answer]).to eq(RagPipeline::NO_CONTEXT_ANSWER)
end
