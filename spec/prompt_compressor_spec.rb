# frozen_string_literal: true

require_relative '../lib/prompt_compressor'

RSpec.describe PromptCompressor do
  subject(:compressor) { described_class.new(counter: TokenCounter.new) }

  let(:passages) do
    [
      { text: 'A política garante trinta dias de férias por ano.', source: 'a.txt', score: 0.9 },
      { text: 'As férias podem ser divididas em três períodos.', source: 'b.txt', score: 0.8 },
      { text: 'O servidor reinicia toda madrugada.', source: 'c.txt', score: 0.7 }
    ]
  end

  describe '#compress' do
    it 'keeps every passage when the budget is enough' do
      expect(compressor.compress(passages, budget: 1000).size).to eq(3)
    end

    it 'drops the least relevant passages when the budget is tight' do
      result = compressor.compress(passages, budget: 30)

      expect(result.map { |passage| passage[:source] }).to eq(%w[a.txt b.txt])
    end

    it 'keeps at least one passage, truncating it if needed' do
      result = compressor.compress(passages, budget: 5)

      expect(result.size).to eq(1)
      expect(result.first[:text].length).to be < passages.first[:text].length
    end

    it 'marks the passage that was truncated' do
      expect(compressor.compress(passages, budget: 5).first[:truncated]).to be(true)
    end

    it 'removes a repeated passage, which would spend tokens saying the same thing twice' do
      repeated = passages + [{ text: 'A política garante trinta dias de férias por ano.', source: 'd.txt' }]

      expect(compressor.compress(repeated, budget: 1000).size).to eq(3)
    end

    it 'treats passages that differ only in whitespace and case as repeated' do
      repeated = [passages.first, { text: '  A POLÍTICA garante   trinta dias de férias por ano. ', source: 'd.txt' }]

      expect(compressor.compress(repeated, budget: 1000).size).to eq(1)
    end

    it 'collapses repeated whitespace inside the text' do
      noisy = [{ text: "linha   com     espaços\n\n\nde sobra", source: 'a.txt' }]

      expect(compressor.compress(noisy, budget: 1000).first[:text]).to eq('linha com espaços de sobra')
    end

    it 'handles an empty list' do
      expect(compressor.compress([], budget: 100)).to eq([])
    end

    it 'reports how many tokens were saved' do
      report = compressor.compress_with_report(passages, budget: 30)

      expect(report[:tokens_before]).to be > report[:tokens_after]
      expect(report[:dropped]).to eq(1)
    end
  end

  describe 'garantia do orçamento' do
    it 'the kept context really fits the budget, even when a passage had to be truncated' do
      counter = TokenCounter.new

      [3, 5, 10, 25].each do |budget|
        result = compressor.compress(passages, budget: budget)
        spent = result.sum { |passage| counter.estimate(passage[:text]) }

        expect(spent).to be <= budget, "orçamento #{budget} estourado: gastou #{spent}"
      end
    end

    it 'returns an empty context when the budget is zero' do
      expect(compressor.compress(passages, budget: 0)).to eq([])
    end
  end
end
