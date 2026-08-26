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

  def search(collection, vector:, limit: 10, filter: nil)
    body = { vector: vector, limit: limit }
    body[:filter] = filter if filter

    response = post("/collections/#{collection}/points/search", body)
    response[:result]
  end

  private

  def put(path, body)
    perform(:put, path, body)
  end

  def post(path, body)
    perform(:post, path, body)
  end

  def perform(method, path, body)
    response = @transport.public_send(method, path, body)
    raise RequestError, "Qdrant request to #{path} failed" unless response[:ok]

    response
  end
end
