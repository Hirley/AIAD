# frozen_string_literal: true

class QdrantClient
  class RequestError < StandardError; end

  def initialize(transport:)
    @transport = transport
  end

  def create_collection(name, vector_size:, distance: 'Cosine')
    put("/collections/#{name}", vectors: { size: vector_size, distance: distance })
  end

  def upsert_points(collection, points)
    put("/collections/#{collection}/points", points: points)
  end

  private

  def put(path, body)
    response = @transport.put(path, body)
    raise RequestError, "Qdrant request to #{path} failed" unless response[:ok]

    response
  end
end
