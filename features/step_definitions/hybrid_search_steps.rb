# frozen_string_literal: true

require_relative '../../lib/etl_pipeline'
require_relative '../../lib/hybrid_retriever'
require_relative '../../lib/rag_pipeline'
require_relative '../../spec/support/fake_llm'
require_relative '../../spec/support/fake_retriever'
require_relative '../../spec/support/in_memory_qdrant_transport'

def hybrid_retriever
  HybridRetriever.new(vector_retriever: @vector_retriever, lexical_index: @lexical_index)
end

def hit_from(source)
  @hits.find { |hit| hit[:payload][:source] == source }
end

Dado('que o assistente indexou nos dois índices os documentos:') do |table|
  @lexical_index = Bm25Index.new
  @etl = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
    embedder: EmbeddingGenerator.new(dimensions: 64),
    lexical_index: @lexical_index
  )

  @payloads = {}
  table.hashes.each do |row|
    @etl.run(row['conteudo'], collection: 'documentos', source: row['origem'], metadata: { autor: row['autor'] })
    @payloads[row['origem']] = @lexical_index.search(row['conteudo'], limit: 1).first
  end

  @vector_retriever = @etl
end

Dado('que o braço vetorial só encontra {string}') do |source|
  hit = @payloads.fetch(source)
  @vector_retriever = FakeRetriever.new(results: [{ id: hit[:id], score: 0.9, payload: hit[:payload] }])
end

Quando('eu busco por {string} com busca híbrida') do |query|
  @hits = hybrid_retriever.search(query, collection: 'documentos')
end

Quando('eu busco por {string} com busca híbrida filtrando pelo autor {string}') do |query, autor|
  @hits = hybrid_retriever.search(
    query, collection: 'documentos', filter: { must: [{ key: 'autor', match: { value: autor } }] }
  )
end

Quando('eu pergunto ao RAG híbrido {string}') do |question|
  @llm = FakeLlm.new
  rag = RagPipeline.new(retriever: hybrid_retriever, llm: @llm, collection: 'documentos', top_k: 1)
  @rag_result = rag.answer(question)
end

Então('o resultado mais relevante deve ser de {string}') do |source|
  expect(@hits.first[:payload][:source]).to eq(source)
end

Então('o resultado mais relevante deve ter sido encontrado pelos dois braços') do
  expect(@hits.first[:matched_by]).to contain_exactly(:vector, :lexical)
end

Então('algum resultado deve ser de {string}') do |source|
  expect(hit_from(source)).not_to be_nil
end

Então('o resultado de {string} deve ter sido encontrado apenas pelo braço léxico') do |source|
  expect(hit_from(source)[:matched_by]).to eq([:lexical])
end

Então('nenhum resultado deve ser de {string}') do |source|
  expect(hit_from(source)).to be_nil
end

Então('a resposta do RAG deve citar a origem {string}') do |source|
  expect(@rag_result[:sources]).to include(source)
end
