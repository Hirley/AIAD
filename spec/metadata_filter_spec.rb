# frozen_string_literal: true

require_relative '../lib/metadata_filter'

RSpec.describe MetadataFilter do
  let(:payload) { { source: 'politica.txt', autor: 'rh', ano: 2026 } }

  describe '.matches?' do
    it 'accepts everything when there is no filter' do
      expect(described_class.matches?(payload, nil)).to be(true)
    end

    it 'matches a single condition' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      expect(described_class.matches?(payload, filter)).to be(true)
    end

    it 'rejects when a condition does not match' do
      filter = { must: [{ key: 'autor', match: { value: 'infra' } }] }

      expect(described_class.matches?(payload, filter)).to be(false)
    end

    it 'requires every condition of must' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }, { key: 'ano', match: { value: 2025 } }] }

      expect(described_class.matches?(payload, filter)).to be(false)
    end

    it 'accepts a symbol key' do
      filter = { must: [{ key: :autor, match: { value: 'rh' } }] }

      expect(described_class.matches?(payload, filter)).to be(true)
    end

    it 'matches any of the values when match uses any' do
      filter = { must: [{ key: 'autor', match: { any: %w[rh infra] } }] }

      expect(described_class.matches?(payload, filter)).to be(true)
    end

    it 'rejects a payload that does not have the key' do
      filter = { must: [{ key: 'inexistente', match: { value: 'x' } }] }

      expect(described_class.matches?(payload, filter)).to be(false)
    end
  end
end
