# frozen_string_literal: true

require_relative '../../lib/etl_pipeline'
require_relative '../../spec/support/fake_qdrant_transport'

COLLECTION = 'documentos'

def indexed_points
  @transport.requests
            .select { |request| request[:path] == "/collections/#{COLLECTION}/points" }
            .flat_map { |request| request[:body][:points] }
end

Dado('que o pipeline de ETL está configurado') do
  @transport = FakeQdrantTransport.new
  @embedder = EmbeddingGenerator.new(dimensions: 32)
  @pipeline = EtlPipeline.new(qdrant: QdrantClient.new(transport: @transport), embedder: @embedder)
end

Quando('eu ingiro o documento {string} no formato {string} com o conteúdo:') do |source, format, content|
  @content = content
  @format = format.to_sym
  @result = @pipeline.run(content, collection: COLLECTION, source: source, format: @format)
end

Quando('eu reprocesso o documento {string} com o mesmo conteúdo') do |source|
  @reprocessed = @pipeline.run(@content, collection: COLLECTION, source: source, format: @format)
end

Quando('eu consulto {string} na coleção {string}') do |query, collection|
  expect(collection).to eq(COLLECTION)
  query_vector = @embedder.embed(query)
  @best_match = indexed_points.max_by do |point|
    EmbeddingGenerator.cosine_similarity(query_vector, point[:vector])
  end
end

Então('a coleção {string} deve ter sido criada com vetores de tamanho {int}') do |collection, size|
  request = @transport.requests.find do |candidate|
    candidate[:method] == :put && candidate[:path] == "/collections/#{collection}"
  end

  expect(request[:body][:vectors][:size]).to eq(size)
end

Então('{int} pontos devem ter sido indexados na coleção {string}') do |count, collection|
  expect(collection).to eq(COLLECTION)
  expect(indexed_points.size).to eq(count)
end

Então('o ponto indexado deve ter origem {string} e formato {string}') do |source, format|
  expect(indexed_points.first[:payload]).to include(source: source, format: format.to_sym)
end

Então('o texto indexado deve ser {string}') do |expected|
  expect(indexed_points.first[:payload][:text]).to eq(expected.gsub('\n', "\n"))
end

Então('os pontos indexados devem ter os mesmos ids do primeiro processamento') do
  expect(@reprocessed[:point_ids]).to eq(@result[:point_ids])
end

Então('o ponto mais similar deve ser o do documento {string}') do |source|
  expect(@best_match[:payload][:source]).to eq(source)
end
