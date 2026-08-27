# frozen_string_literal: true

require_relative '../lib/model_router'

RSpec.describe ModelRouter do
  let(:fast) { FakeLlm.new(response: 'resposta barata') }
  let(:strong) { FakeLlm.new(response: 'resposta cara') }

  subject(:router) { described_class.new(fast: fast, strong: strong, threshold_tokens: 50) }

  describe '#complete' do
    it 'sends a short and simple prompt to the cheap model' do
      expect(router.complete('Qual o horário de almoço?')).to eq('resposta barata')
    end

    it 'sends a long prompt to the strong model' do
      expect(router.complete('palavra ' * 200)).to eq('resposta cara')
    end

    it 'sends an analytical question to the strong model even when it is short' do
      expect(router.complete('Compare as duas políticas.')).to eq('resposta cara')
    end

    it 'reports which model answered' do
      router.complete('Qual o horário de almoço?')

      expect(router.last_choice).to eq(:fast)
    end

    it 'only calls the chosen model' do
      router.complete('Qual o horário de almoço?')

      expect(strong.prompts).to be_empty
    end

    it 'uses the injected classifier' do
      always_strong = described_class.new(fast: fast, strong: strong, classifier: ->(_prompt) { :strong })

      expect(always_strong.complete('oi')).to eq('resposta cara')
    end

    it 'falls back to the strong model when the classifier returns something unknown' do
      confused = described_class.new(fast: fast, strong: strong, classifier: ->(_prompt) { :sei_la })

      expect(confused.complete('oi')).to eq('resposta cara')
    end
  end
end
