# frozen_string_literal: true

require_relative '../lib/reranker'

RSpec.describe Reranker do
  subject(:reranker) { described_class.new }

  let(:hits) do
    [
      { id: 1, score: 0.9, payload: { text: 'O cluster de produção reinicia toda madrugada' } },
      { id: 2, score: 0.8, payload: { text: 'O erro ERR-4021 derruba o cluster de produção na madrugada' } },
      { id: 3, score: 0.7, payload: { text: 'Política de férias e trinta dias por ano' } }
    ]
  end

  describe '#rerank' do
    it 'puts the passage that covers more query terms first' do
      result = reranker.rerank('erro ERR-4021 no cluster', hits)

      expect(result.first[:id]).to eq(2)
    end

    it 'demotes the passage that covers nothing' do
      result = reranker.rerank('erro ERR-4021 no cluster', hits)

      expect(result.last[:id]).to eq(3)
    end

    it 'reports the rerank score of each passage' do
      result = reranker.rerank('cluster', hits)

      expect(result.first).to have_key(:rerank_score)
    end

    it 'keeps the original order between passages with the same coverage' do
      result = reranker.rerank('cluster produção', hits)

      expect(result.map { |hit| hit[:id] }.first(2)).to eq([1, 2])
    end

    it 'respects the limit' do
      expect(reranker.rerank('cluster', hits, limit: 2).size).to eq(2)
    end

    it 'handles an empty list' do
      expect(reranker.rerank('qualquer', [])).to eq([])
    end

    it 'gives zero to a hit without text instead of blowing up' do
      result = reranker.rerank('cluster', [{ id: 9, payload: {} }])

      expect(result.first[:rerank_score]).to eq(0.0)
    end

    it 'uses the injected scorer, for a real cross-encoder' do
      scorer = ->(_query, text) { text.length.to_f }

      result = described_class.new(scorer: scorer).rerank('irrelevante', hits)

      expect(result.first[:id]).to eq(2)
    end

    it 'does not change the original list' do
      original = hits.map { |hit| hit[:id] }

      reranker.rerank('cluster', hits)

      expect(hits.map { |hit| hit[:id] }).to eq(original)
    end
  end
end
