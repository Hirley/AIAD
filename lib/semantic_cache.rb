# frozen_string_literal: true

require_relative 'embedding_generator'

# Cache semântico: reaproveita a resposta de uma pergunta parecida, não só da
# pergunta idêntica.
#
# Duas pessoas raramente escrevem a mesma pergunta do mesmo jeito, e é aí que o
# cache por chave exata falha. Aqui a chave é o embedding: se a similaridade com
# alguma pergunta guardada passar do limiar, devolve a resposta dela.
#
# O limiar é a decisão delicada: baixo demais devolve resposta de outra pergunta.
class SemanticCache
  DEFAULT_THRESHOLD = 0.92
  DEFAULT_MAX_ENTRIES = 500

  def initialize(embedder: EmbeddingGenerator.new, threshold: DEFAULT_THRESHOLD, max_entries: DEFAULT_MAX_ENTRIES)
    @embedder = embedder
    @threshold = threshold
    @max_entries = max_entries
    @entries = {}
    @hits = 0
    @misses = 0
  end

  def fetch(query)
    entry = nearest(@embedder.embed(query))

    if entry
      @hits += 1
      entry[:value]
    else
      @misses += 1
      nil
    end
  end

  def store(query, value)
    vector = @embedder.embed(query)
    @entries[query] = { vector: vector, value: value }
    @entries.shift while @entries.size > @max_entries

    value
  end

  def size
    @entries.size
  end

  def stats
    { hits: @hits, misses: @misses, entries: size }
  end

  private

  def nearest(vector)
    best = @entries.values.max_by { |entry| EmbeddingGenerator.cosine_similarity(vector, entry[:vector]) }
    return nil if best.nil?

    EmbeddingGenerator.cosine_similarity(vector, best[:vector]) >= @threshold ? best : nil
  end
end
