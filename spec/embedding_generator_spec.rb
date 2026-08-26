# frozen_string_literal: true

require_relative '../lib/embedding_generator'

RSpec.describe EmbeddingGenerator do
  subject(:generator) { described_class.new(dimensions: 16) }

  describe '#embed' do
    it 'returns a vector with the configured number of dimensions' do
      expect(generator.embed('contrato de prestação de serviços').size).to eq(16)
    end

    it 'is deterministic for the same text' do
      expect(generator.embed('relatório anual')).to eq(generator.embed('relatório anual'))
    end

    it 'produces different vectors for different texts' do
      expect(generator.embed('contrato')).not_to eq(generator.embed('fatura'))
    end

    it 'returns a unit vector' do
      magnitude = Math.sqrt(generator.embed('documento fiscal').sum { |value| value * value })

      expect(magnitude).to be_within(0.0001).of(1.0)
    end

    it 'ignores case and punctuation' do
      expect(generator.embed('Contrato, assinado!')).to eq(generator.embed('contrato assinado'))
    end

    it 'raises when the text is blank' do
      expect { generator.embed('   ') }.to raise_error(EmbeddingGenerator::BlankTextError)
    end

    it 'uses the injected provider when one is given' do
      provider = ->(text) { [text.length.to_f, 0.0] }

      expect(described_class.new(provider: provider).embed('abc')).to eq([3.0, 0.0])
    end
  end

  describe '#embed_all' do
    it 'returns one vector per text' do
      expect(generator.embed_all(%w[contrato fatura]).size).to eq(2)
    end
  end

  describe '.cosine_similarity' do
    it 'returns 1.0 for identical vectors' do
      vector = generator.embed('nota fiscal eletrônica')

      expect(described_class.cosine_similarity(vector, vector)).to be_within(0.0001).of(1.0)
    end

    it 'scores texts that share terms higher than unrelated ones' do
      query = generator.embed('contrato de aluguel')
      related = generator.embed('contrato de aluguel residencial')
      unrelated = generator.embed('manual técnico do servidor')

      expect(described_class.cosine_similarity(query, related))
        .to be > described_class.cosine_similarity(query, unrelated)
    end

    it 'raises when the vectors have different sizes' do
      expect { described_class.cosine_similarity([1.0], [1.0, 2.0]) }.to raise_error(ArgumentError)
    end
  end
end
