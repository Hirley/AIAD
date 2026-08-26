# frozen_string_literal: true

class QdrantClient
  class RequestError < StandardError; end

  def initialize(transport:)
    @transport = transport
  end

  def create_collection(name, vector_size:, distance: 'Cosine', hnsw: nil, quantization: nil)
    body = merge_present(
      { vectors: { size: vector_size, distance: distance } },
      hnsw_config: hnsw, quantization_config: quantization
    )

    put(collection_path(name), body)
  end

  # Ajuste de índice em coleção já existente (tuning sem reindexar do zero).
  def update_collection(name, hnsw: nil, optimizers: nil)
    body = merge_present({}, hnsw_config: hnsw, optimizers_config: optimizers)
    raise ArgumentError, 'nothing to update' if body.empty?

    patch(collection_path(name), body)
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

  # `params` aceita os ajustes de busca do Qdrant, por exemplo
  # `{ hnsw_ef: 128, exact: false, quantization: { rescore: true } }`.
  def search(collection, vector:, limit: 10, filter: nil, params: nil)
    body = merge_present({ vector: vector, limit: limit }, filter: filter, params: presence(params))
    response = post("#{collection_path(collection)}/points/search", body)
    response[:result]
  end

  def count_points(collection, filter: nil)
    response = post("#{collection_path(collection)}/points/count", merge_present({}, filter: filter))
    response.dig(:result, :count)
  end

  private

  def collection_path(name)
    "/collections/#{name}"
  end

  # Acrescenta ao corpo apenas as chaves opcionais que foram informadas.
  def merge_present(body, extra)
    body.merge(extra.compact)
  end

  def presence(hash)
    return nil if hash.nil? || hash.empty?

    hash.compact
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

  def patch(path, body)
    ensure_success(@transport.patch(path, body), path)
  end

  def delete(path)
    ensure_success(@transport.delete(path), path)
  end

  def ensure_success(response, path)
    raise RequestError, "Qdrant request to #{path} failed" unless response[:ok]

    response
  end
end
