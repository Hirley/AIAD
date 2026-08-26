# frozen_string_literal: true

require 'digest'

require_relative 'tokenizer'

# Gera embeddings (vetorização de texto) para os chunks de documentos.
#
# Por padrão usa o "hashing trick": cada termo é projetado de forma determinística
# em uma posição do vetor, que é normalizado no fim. Não depende de rede nem de
# modelo externo, o que mantém os testes rápidos e reprodutíveis.
#
# Para usar um modelo real (OpenAI, Cohere, sentence-transformers etc.) basta
# injetar um provider: `EmbeddingGenerator.new(provider: ->(texto) { ... })`.
class EmbeddingGenerator
  class BlankTextError < StandardError; end

  DEFAULT_DIMENSIONS = 256

  attr_reader :dimensions

  def initialize(dimensions: DEFAULT_DIMENSIONS, provider: nil)
    raise ArgumentError, 'dimensions must be positive' unless dimensions.positive?

    @dimensions = dimensions
    @provider = provider
  end

  def embed(text)
    raise BlankTextError, 'text cannot be blank' if text.nil? || text.strip.empty?
    return @provider.call(text) if @provider

    normalize(project(Tokenizer.tokens(text)))
  end

  def embed_all(texts)
    texts.map { |text| embed(text) }
  end

  def self.cosine_similarity(vector_a, vector_b)
    raise ArgumentError, 'vectors must have the same size' unless vector_a.size == vector_b.size

    magnitude_a = Math.sqrt(vector_a.sum { |value| value * value })
    magnitude_b = Math.sqrt(vector_b.sum { |value| value * value })
    return 0.0 if magnitude_a.zero? || magnitude_b.zero?

    dot_product(vector_a, vector_b) / (magnitude_a * magnitude_b)
  end

  def self.dot_product(vector_a, vector_b)
    vector_a.each_with_index.sum { |value, index| value * vector_b[index] }
  end
  private_class_method :dot_product

  private

  def project(tokens)
    tokens.each_with_object(Array.new(@dimensions, 0.0)) do |token, vector|
      digest = Digest::SHA256.hexdigest(token).to_i(16)
      vector[digest % @dimensions] += digest.even? ? 1.0 : -1.0
    end
  end

  def normalize(vector)
    magnitude = Math.sqrt(vector.sum { |value| value * value })
    return vector if magnitude.zero?

    vector.map { |value| value / magnitude }
  end
end
