# frozen_string_literal: true

require_relative '../lib/semantic_cache'

RSpec.describe SemanticCache do
  let(:embedder) { EmbeddingGenerator.new(dimensions: 64) }

  subject(:cache) { described_class.new(embedder: embedder, threshold: 0.8) }

  describe '#fetch' do
    it 'misses on an empty cache' do
      expect(cache.fetch('qualquer pergunta')).to be_nil
    end

    it 'hits the exact same question' do
      cache.store('quantos dias de férias por ano', 'Trinta dias.')

      expect(cache.fetch('quantos dias de férias por ano')).to eq('Trinta dias.')
    end

    it 'hits a rewording of the same question' do
      cache.store('quantos dias de férias por ano', 'Trinta dias.')

      expect(cache.fetch('quantos dias de férias temos por ano')).to eq('Trinta dias.')
    end

    it 'misses an unrelated question' do
      cache.store('quantos dias de férias por ano', 'Trinta dias.')

      expect(cache.fetch('quando o servidor reinicia')).to be_nil
    end

    it 'misses the rewording when the threshold is strict' do
      strict = described_class.new(embedder: embedder, threshold: 0.999)
      strict.store('quantos dias de férias por ano', 'Trinta dias.')

      expect(strict.fetch('quantos dias de férias temos por ano')).to be_nil
    end
  end

  describe '#store' do
    it 'replaces the value of a question already cached' do
      cache.store('mesma pergunta', 'antiga')
      cache.store('mesma pergunta', 'nova')

      expect(cache.fetch('mesma pergunta')).to eq('nova')
      expect(cache.size).to eq(1)
    end

    it 'evicts the oldest entry beyond the limit' do
      small = described_class.new(embedder: embedder, threshold: 0.99, max_entries: 2)
      small.store('primeira pergunta sobre férias', 'a')
      small.store('segunda pergunta sobre servidor', 'b')
      small.store('terceira pergunta sobre contrato', 'c')

      expect(small.size).to eq(2)
      expect(small.fetch('primeira pergunta sobre férias')).to be_nil
    end
  end

  describe '#stats' do
    it 'counts hits and misses' do
      cache.store('pergunta cacheada', 'valor')
      cache.fetch('pergunta cacheada')
      cache.fetch('outra coisa bem diferente')

      expect(cache.stats).to include(hits: 1, misses: 1, entries: 1)
    end
  end
end
