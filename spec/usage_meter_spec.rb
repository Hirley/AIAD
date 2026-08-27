# frozen_string_literal: true

require_relative '../lib/usage_meter'

RSpec.describe UsageMeter do
  subject(:meter) { described_class.new(prices: { 'modelo-caro' => { input: 3.0, output: 15.0 } }) }

  describe '#record' do
    it 'returns the usage of the call' do
      usage = meter.record(model: 'modelo-caro', prompt_tokens: 1000, completion_tokens: 500)

      expect(usage).to include(prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500)
    end

    it 'prices the call by the configured rate per million tokens' do
      usage = meter.record(model: 'modelo-caro', prompt_tokens: 1_000_000, completion_tokens: 1_000_000)

      expect(usage[:cost]).to be_within(0.0001).of(18.0)
    end

    it 'charges nothing for a model without a configured price' do
      expect(meter.record(model: 'desconhecido', prompt_tokens: 100, completion_tokens: 100)[:cost]).to eq(0.0)
    end
  end

  describe '#totals' do
    it 'accumulates across calls' do
      meter.record(model: 'modelo-caro', prompt_tokens: 100, completion_tokens: 50)
      meter.record(model: 'modelo-caro', prompt_tokens: 200, completion_tokens: 100)

      expect(meter.totals).to include(calls: 2, prompt_tokens: 300, completion_tokens: 150, total_tokens: 450)
    end

    it 'starts at zero' do
      expect(meter.totals).to include(calls: 0, total_tokens: 0, cost: 0.0)
    end
  end

  describe '#by_model' do
    it 'breaks the usage down per model' do
      meter.record(model: 'modelo-caro', prompt_tokens: 100, completion_tokens: 10)
      meter.record(model: 'outro', prompt_tokens: 50, completion_tokens: 5)

      expect(meter.by_model.keys).to contain_exactly('modelo-caro', 'outro')
      expect(meter.by_model['outro'][:total_tokens]).to eq(55)
    end
  end
end
