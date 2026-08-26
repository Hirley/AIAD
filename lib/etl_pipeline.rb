# frozen_string_literal: true

require 'digest'

require_relative 'bm25_index'
require_relative 'content_cleaner'
require_relative 'document_chunker'
require_relative 'document_ingestor'
require_relative 'embedding_generator'
require_relative 'qdrant_client'

# Pipeline de ETL: ingere conteúdo não estruturado (texto, log ou PDF extraído),
# limpa, estrutura em chunks, gera os embeddings e indexa os pontos no Qdrant.
#
# Todas as dependências são injetáveis, então o pipeline é testável de ponta a
# ponta sem servidor Qdrant nem chamada a modelo de embeddings.
class EtlPipeline
  DEFAULT_CHUNK_SIZE = 500
  DEFAULT_OVERLAP = 50
  ID_BITS = 48

  def initialize(qdrant:, embedder: EmbeddingGenerator.new, chunker: nil, ingestor: DocumentIngestor.new,
                 cleaner: ContentCleaner.new, lexical_index: nil)
    @qdrant = qdrant
    @embedder = embedder
    @chunker = chunker || DocumentChunker.new(chunk_size: DEFAULT_CHUNK_SIZE, overlap: DEFAULT_OVERLAP)
    @ingestor = ingestor
    @cleaner = cleaner
    @lexical_index = lexical_index
  end

  def run(content, collection:, source:, format: :texto, metadata: {})
    chunks = extract(content, format: format)
    points = build_points(chunks, source: source, format: format, metadata: metadata)

    ensure_collection(collection)
    @qdrant.upsert_points(collection, points)
    index_lexically(points)

    { collection: collection, source: source, format: format, chunks: points.size,
      point_ids: points.map { |point| point[:id] } }
  end

  def search(query, collection:, limit: 10, filter: nil, params: nil)
    @qdrant.search(collection, vector: @embedder.embed(query), limit: limit, filter: filter, params: params)
  end

  private

  def extract(content, format:)
    @chunker.chunk(@cleaner.clean(@ingestor.ingest(content), format: format))
  end

  def build_points(chunks, source:, format:, metadata:)
    chunks.each_with_index.map do |chunk, index|
      {
        id: point_id(source, index),
        vector: @embedder.embed(chunk),
        payload: metadata.merge(source: source, format: format, chunk_index: index, text: chunk)
      }
    end
  end

  # A mesma ingestão alimenta os dois braços da busca híbrida: o vetorial, no
  # Qdrant, e o léxico BM25, em memória.
  def index_lexically(points)
    return if @lexical_index.nil?

    points.each { |point| @lexical_index.add(point[:id], point[:payload][:text], payload: point[:payload]) }
  end

  # Id determinístico: reprocessar a mesma origem atualiza os pontos existentes
  # em vez de duplicá-los.
  def point_id(source, index)
    Digest::SHA256.hexdigest("#{source}##{index}").to_i(16) % (2**ID_BITS)
  end

  def ensure_collection(collection)
    return if @qdrant.collection_exists?(collection)

    @qdrant.create_collection(collection, vector_size: @embedder.dimensions)
  end
end
