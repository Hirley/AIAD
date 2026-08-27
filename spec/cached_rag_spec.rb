# frozen_string_literal: true

require_relative '../lib/cached_rag'

RSpec.describe CachedRag do
  let(:hits) do
    [{ id: 1, score: 0.9, payload: { text: 'Trinta dias de férias por ano.', source: 'politica.txt' } }]
  end
  let(:llm) { FakeLlm.new }
  let(:inner) do
    RagPipeline.new(retriever: FakeRetriever.new(results: hits), llm: llm, collection: 'documentos')
  end
  let(:embedder) { EmbeddingGenerator.new(dimensions: 64) }

  subject(:rag) do
    described_class.new(rag: inner, cache_factory: -> { SemanticCache.new(embedder: embedder, threshold: 0.8) })
  end

  describe '#answer' do
    it 'answers normally on a miss' do
      result = rag.answer('quantos dias de férias por ano')

      expect(result[:answer]).to eq('Trinta dias por ano [1].')
      expect(result[:cached]).to be(false)
    end

    it 'serves a reworded question from the cache' do
      rag.answer('quantos dias de férias por ano')
      result = rag.answer('quantos dias de férias temos por ano')

      expect(result[:answer]).to eq('Trinta dias por ano [1].')
      expect(result[:cached]).to be(true)
    end

    it 'does not call the model again on a hit' do
      rag.answer('quantos dias de férias por ano')
      rag.answer('quantos dias de férias temos por ano')

      expect(llm.prompts.size).to eq(1)
    end

    it 'reports no token spending on a hit' do
      rag.answer('quantos dias de férias por ano')

      expect(rag.answer('quantos dias de férias temos por ano')[:usage][:total_tokens]).to eq(0)
    end

    it 'does not cache an answer that had no context' do
      without_context = described_class.new(
        rag: RagPipeline.new(retriever: FakeRetriever.new(results: []), llm: llm, collection: 'documentos'),
        cache_factory: -> { SemanticCache.new(embedder: embedder, threshold: 0.8) }
      )

      without_context.answer('pergunta sem resposta')

      expect(without_context.stats[:entries]).to eq(0)
    end

    it 'does not serve an answer cached under a different metadata filter' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      rag.answer('quantos dias de férias por ano')
      result = rag.answer('quantos dias de férias por ano', filter: filter)

      expect(result[:cached]).to be(false)
    end

    it 'reuses the cache of the same filter' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      rag.answer('quantos dias de férias por ano', filter: filter)

      expect(rag.answer('quantos dias de férias por ano', filter: filter)[:cached]).to be(true)
    end
  end

  describe '#stats' do
    it 'aggregates hits and misses across filters' do
      rag.answer('quantos dias de férias por ano')
      rag.answer('quantos dias de férias temos por ano')

      expect(rag.stats).to include(hits: 1, misses: 1)
    end
  end
end
