# frozen_string_literal: true

require_relative '../../lib/api/access_policy'

RSpec.describe Api::AccessPolicy do
  describe '.scope_for' do
    it 'leaves the health check public' do
      expect(described_class.scope_for('GET', '/health')).to be_nil
    end

    # Escopo próprio, e não `read`: o Prometheus não precisa ler documento para
    # raspar métrica, e quem lê documento não precisa ver a operação por dentro.
    it 'requires its own scope to scrape the metrics' do
      expect(described_class.scope_for('GET', '/metrics')).to eq(:metrics)
    end

    it 'does not leave the metrics public, unlike the health check' do
      expect(described_class.scope_for('GET', '/metrics')).not_to be_nil
    end

    it 'requires write to ingest documents' do
      expect(described_class.scope_for('POST', '/documents')).to eq(:write)
    end

    it 'requires read to search' do
      expect(described_class.scope_for('POST', '/search')).to eq(:read)
    end

    it 'requires read to ask' do
      expect(described_class.scope_for('POST', '/ask')).to eq(:read)
    end

    it 'requires the most restrictive scope for an unmapped route, so a new endpoint is never public by accident' do
      expect(described_class.scope_for('POST', '/rota-nova')).to eq(:write)
    end

    it 'distinguishes the method, so reading a route does not grant writing to it' do
      expect(described_class.scope_for('GET', '/documents')).to eq(:write)
    end
  end
end
