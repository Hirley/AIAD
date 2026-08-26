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
