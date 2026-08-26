# frozen_string_literal: true

class QdrantClient
  class RequestError < StandardError; end

  def initialize(transport:)
    @transport = transport
  end

  def create_collection(name, vector_size:, distance: 'Cosine')
    put(collection_path(name), vectors: { size: vector_size, distance: distance })
  end

  def collection_exists?(name)
    response = get("#{collection_path(name)}/exists")
    response.dig(:result, :exists) == true
  end

  def delete_collection(name)
    delete(collection_path(name))
  end

  def upsert_points(collection, points)
    put("#{collection_path(collection)}/points", points: points)
  end

  def delete_points(collection, ids)
    post("#{collection_path(collection)}/points/delete", points: ids)
  end

  def search(collection, vector:, limit: 10, filter: nil)
    body = with_filter({ vector: vector, limit: limit }, filter)
    response = post("#{collection_path(collection)}/points/search", body)
    response[:result]
  end

  def count_points(collection, filter: nil)
    response = post("#{collection_path(collection)}/points/count", with_filter({}, filter))
    response.dig(:result, :count)
  end

  private

  def collection_path(name)
    "/collections/#{name}"
  end

  def with_filter(body, filter)
    return body unless filter

    body.merge(filter: filter)
  end

  def get(path)
    ensure_success(@transport.get(path), path)
  end

  def put(path, body)
    ensure_success(@transport.put(path, body), path)
  end

  def post(path, body)
    ensure_success(@transport.post(path, body), path)
  end

  def delete(path)
    ensure_success(@transport.delete(path), path)
  end

  def ensure_success(response, path)
    raise RequestError, "Qdrant request to #{path} failed" unless response[:ok]

    response
  end
end
