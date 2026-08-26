# frozen_string_literal: true

require_relative '../../lib/qdrant_client'
require_relative '../../spec/support/fake_qdrant_transport'

Dado('que o Qdrant está disponível') do
  @transport = FakeQdrantTransport.new
  @client = QdrantClient.new(transport: @transport)
end

Quando('eu crio a coleção {string} com vetores de tamanho {int} e distância {string}') do |name, size, distance|
  @collection = name
  @create_response = @client.create_collection(name, vector_size: size, distance: distance)
end

Quando('eu indexo os pontos dos chunks {string} e {string} na coleção {string}') do |chunk_a, chunk_b, collection|
  points = [chunk_a, chunk_b].each_with_index.map do |chunk, index|
    { id: index + 1, vector: chunk.bytes.first(3), payload: { chunk: chunk } }
  end
  @client.upsert_points(collection, points)
end

Então('a coleção {string} deve ter sido criada com sucesso') do |name|
  expect(@create_response[:ok]).to be(true)
  expect(@transport.requests.first[:path]).to eq("/collections/#{name}")
end

Então('{int} pontos devem ter sido enviados para a coleção {string}') do |count, collection|
  points_request = @transport.requests.find { |r| r[:path] == "/collections/#{collection}/points" }
  expect(points_request[:body][:points].size).to eq(count)
end

Dado('a coleção {string} possui pontos que respondem a uma busca com os resultados:') do |collection, table|
  results = table.hashes.map { |row| { id: row['id'].to_i, score: row['score'].to_f } }
  @transport.stub_response("/collections/#{collection}/points/search", { ok: true, result: results })
end

Quando('eu busco na coleção {string} os {int} pontos mais próximos do vetor {string}') do |collection, limit, vector|
  @search_result = @client.search(collection, vector: vector.split(',').map(&:to_f), limit: limit)
end

Então('devo receber {int} resultados da busca') do |count|
  expect(@search_result.size).to eq(count)
end

Então('o resultado mais relevante deve ser o ponto de id {string}') do |id|
  expect(@search_result.first[:id]).to eq(id.to_i)
end

Quando('eu busco na coleção {string} os {int} pontos mais próximos do vetor {string} com filtro {string}={string}') \
  do |collection, limit, vector, field, value|
  filter = { must: [{ key: field, match: { value: value } }] }
  @search_result = @client.search(collection, vector: vector.split(',').map(&:to_f), limit: limit, filter: filter)
end

Então('a busca deve ter usado o filtro de metadado {string} com valor {string}') do |field, value|
  expect(@transport.requests.last[:body][:filter]).to eq(must: [{ key: field, match: { value: value } }])
end
