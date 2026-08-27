# frozen_string_literal: true

require_relative '../lib/token_counter'

RSpec.describe TokenCounter do
  subject(:counter) { described_class.new }

  describe '#estimate' do
    it 'counts more tokens for a longer text' do
      expect(counter.estimate('texto bem mais longo do que o outro')).to be > counter.estimate('curto')
    end

    it 'counts at least one token for a non-empty text' do
      expect(counter.estimate('a')).to eq(1)
    end

    it 'counts zero for empty or nil' do
      expect(counter.estimate('')).to eq(0)
      expect(counter.estimate(nil)).to eq(0)
    end

    it 'estimates roughly four characters per token' do
      expect(counter.estimate('a' * 40)).to be_within(3).of(10)
    end

    it 'counts a word-heavy text by words when that is larger' do
      # Muitas palavras curtas: contar só por caractere subestimaria.
      expect(counter.estimate('a e o de da do em um')).to be >= 8
    end

    it 'uses the injected counter, for a real tokenizer' do
      exact = described_class.new(counter: ->(text) { text.split.size })

      expect(exact.estimate('uma frase de cinco palavras')).to eq(5)
    end
  end

  describe '#fits?' do
    it 'says whether the text fits the budget' do
      expect(counter.fits?('a' * 40, limit: 100)).to be(true)
      expect(counter.fits?('a' * 4000, limit: 100)).to be(false)
    end
  end
end
