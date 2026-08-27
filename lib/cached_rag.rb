# frozen_string_literal: true

require_relative 'semantic_cache'

# Cache semântico na frente do RAG: pergunta parecida já respondida não volta
# para o modelo.
#
# É um decorador, com a mesma interface do RagPipeline, para que o pipeline não
# precise saber que existe cache.
#
# Há um cache por filtro de metadados, e não um só: a resposta a "quanto é o
# reajuste" restrita ao autor "rh" não pode ser servida para quem perguntou o
# mesmo sem esse recorte — seria vazamento de conteúdo entre recortes
# diferentes.
class CachedRag
  def initialize(rag:, cache_factory: -> { SemanticCache.new })
    @rag = rag
    @cache_factory = cache_factory
    @caches = {}
  end

  def answer(question, filter: nil)
    cache = cache_for(filter)
    cached = cache.fetch(question)
    return cached.merge(cached: true, usage: RagPipeline::NO_USAGE) if cached

    result = @rag.answer(question, filter: filter)
    # Resposta sem contexto não vira cache: se o documento for indexado depois,
    # a próxima pergunta precisa tentar de novo.
    cache.store(question, result) unless result[:passages].empty?

    result
  end

  def stats
    @caches.values.each_with_object({ hits: 0, misses: 0, entries: 0 }) do |cache, totals|
      cache.stats.each { |key, value| totals[key] += value }
    end
  end

  private

  def cache_for(filter)
    @caches[filter.inspect] ||= @cache_factory.call
  end
end
