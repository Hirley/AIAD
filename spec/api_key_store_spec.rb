# frozen_string_literal: true

require_relative '../lib/api_key_store'

RSpec.describe ApiKeyStore do
  subject(:store) { described_class.parse('leitor:chave-leitura:read;robo:chave-total:read,write') }

  describe '#authenticate' do
    it 'returns the principal for a valid key' do
      expect(store.authenticate('chave-leitura')).to eq(name: 'leitor', scopes: %i[read])
    end

    it 'reads every configured key' do
      expect(store.authenticate('chave-total')).to eq(name: 'robo', scopes: %i[read write])
    end

    it 'returns nil for an unknown key' do
      expect(store.authenticate('chave-errada')).to be_nil
    end

    it 'returns nil for a blank token' do
      expect(store.authenticate(nil)).to be_nil
      expect(store.authenticate('')).to be_nil
    end

    it 'does not accept a prefix of a valid key' do
      expect(store.authenticate('chave-leitur')).to be_nil
    end

    it 'does not accept a key with trailing content' do
      expect(store.authenticate('chave-leituraX')).to be_nil
    end
  end

  describe '.parse' do
    it 'ignores whitespace and empty entries' do
      parsed = described_class.parse(' leitor : chave : read ;; ')

      expect(parsed.authenticate('chave')).to eq(name: 'leitor', scopes: %i[read])
    end

    it 'builds an empty store from a blank configuration' do
      expect(described_class.parse(nil)).to be_empty
    end

    it 'rejects a malformed entry, failing at boot instead of at the first request' do
      expect { described_class.parse('so-o-nome') }.to raise_error(ApiKeyStore::ConfigurationError)
    end

    it 'rejects an entry without scopes' do
      expect { described_class.parse('nome:chave:') }.to raise_error(ApiKeyStore::ConfigurationError)
    end

    it 'rejects an unknown scope' do
      expect { described_class.parse('nome:chave:admin') }.to raise_error(ApiKeyStore::ConfigurationError)
    end
  end

  describe '#names' do
    it 'lists the configured principals' do
      expect(store.names).to eq(%w[leitor robo])
    end
  end

  describe 'proteção dos segredos' do
    it 'does not expose the keys when inspected' do
      expect(store.inspect).not_to include('chave-leitura')
    end

    it 'shows the principal names when inspected, to help debugging' do
      expect(store.inspect).to include('leitor')
    end
  end
end
