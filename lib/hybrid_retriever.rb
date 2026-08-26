# frozen_string_literal: true

require_relative 'bm25_index'
require_relative 'metadata_filter'

# Busca híbrida: combina o braço vetorial (semântico) com o braço léxico BM25.
#
# A fusão usa Reciprocal Rank Fusion — cada braço contribui com 1/(k + posição).
# Trabalhar com posição, e não com o score bruto, evita ter que normalizar
# escalas incomparáveis (similaridade de cosseno x score BM25) e dá peso extra
# ao que os dois braços concordam em trazer para o topo.
#
# Expõe a mesma interface de `EtlPipeline#search`, então o RagPipeline aceita
# este recuperador sem nenhuma mudança.
class HybridRetriever
  DEFAULT_RRF_K = 60
  DEFAULT_POOL = 20

  def initialize(vector_retriever:, lexical_index:, rrf_k: DEFAULT_RRF_K, pool: DEFAULT_POOL)
    @vector_retriever = vector_retriever
    @lexical_index = lexical_index
    @rrf_k = rrf_k
    @pool = pool
  end

  def search(query, collection:, limit: 10, filter: nil, params: nil)
    fused = {}

    fuse(fused, vector_hits(query, collection, filter, params), :vector)
    fuse(fused, lexical_hits(query, filter), :lexical)

    fused.values.sort_by { |hit| -hit[:score] }.first(limit)
  end

  private

  def vector_hits(query, collection, filter, params)
    @vector_retriever.search(query, collection: collection, limit: @pool, filter: filter, params: params) || []
  end

  # O Qdrant já devolve o recorte filtrado; no índice léxico o filtro é aplicado
  # aqui, sobre o payload guardado na indexação.
  def lexical_hits(query, filter)
    @lexical_index.search(query, limit: @pool)
                  .select { |hit| MetadataFilter.matches?(hit[:payload], filter) }
  end

  def fuse(fused, hits, arm)
    hits.each_with_index do |hit, index|
      entry = fused[hit[:id]] ||= { id: hit[:id], score: 0.0, payload: hit[:payload], matched_by: [] }
      entry[:payload] ||= hit[:payload]
      entry[:score] += 1.0 / (@rrf_k + index + 1)
      entry[:matched_by] << arm
    end
  end
end
