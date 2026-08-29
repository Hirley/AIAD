# frozen_string_literal: true

require 'json'

require_relative '../lib/anthropic_llm'

RSpec.describe AnthropicLlm do
  # Transporte de mentira no lugar da rede: guarda o pedido e devolve a
  # resposta combinada. É o que deixa a suíte rodar sem chave e sem internet.
  let(:transport) do
    FakeHttpClient.new(code: '200', body: JSON.generate(content: [{ type: 'text', text: 'trinta dias' }]))
  end

  subject(:llm) { described_class.new(api_key: 'chave-de-teste', model: 'claude-sonnet-5', client: transport) }

  describe '#complete' do
    it 'returns the text the model generated' do
      expect(llm.complete('quantos dias de férias?')).to eq('trinta dias')
    end

    it 'sends the prompt as a user message' do
      llm.complete('quantos dias de férias?')

      expect(JSON.parse(transport.requests.last.body)['messages'])
        .to eq([{ 'role' => 'user', 'content' => 'quantos dias de férias?' }])
    end

    it 'sends the configured model' do
      llm.complete('pergunta')

      expect(JSON.parse(transport.requests.last.body)['model']).to eq('claude-sonnet-5')
    end

    it 'authenticates with the key' do
      llm.complete('pergunta')

      expect(transport.requests.last['x-api-key']).to eq('chave-de-teste')
    end

    it 'declares the API version, which the provider requires' do
      llm.complete('pergunta')

      expect(transport.requests.last['anthropic-version']).to eq(described_class::API_VERSION)
    end

    # A resposta vem em blocos; só os de texto interessam.
    it 'joins the text blocks in order' do
      transport.body = JSON.generate(content: [{ type: 'text', text: 'trinta ' }, { type: 'text', text: 'dias' }])

      expect(llm.complete('pergunta')).to eq('trinta dias')
    end

    it 'ignores a block that is not text' do
      transport.body = JSON.generate(content: [{ type: 'thinking', thinking: 'hmm' },
                                               { type: 'text', text: 'trinta dias' }])

      expect(llm.complete('pergunta')).to eq('trinta dias')
    end
  end

  describe 'quando o provedor recusa' do
    it 'raises with the status' do
      transport.code = '429'
      transport.body = JSON.generate(error: { message: 'rate limit' })

      expect { llm.complete('pergunta') }.to raise_error(described_class::Error, /429/)
    end

    it 'carries the message the provider gave, which is what says what to fix' do
      transport.code = '400'
      transport.body = JSON.generate(error: { message: 'max_tokens acima do limite' })

      expect { llm.complete('pergunta') }.to raise_error(described_class::Error, /max_tokens/)
    end

    it 'raises instead of returning empty text when there is no content' do
      transport.body = JSON.generate(id: 'msg_1')

      expect { llm.complete('pergunta') }.to raise_error(described_class::Error, /sem conteúdo/)
    end

    # Quem chama trata Error, não exceção de socket.
    it 'wraps a network failure' do
      allow(transport).to receive(:request).and_raise(Errno::ECONNREFUSED)

      expect { llm.complete('pergunta') }.to raise_error(described_class::Error, /falha de rede/)
    end
  end

  describe '.from_env' do
    it 'builds the client when there is a key' do
      expect(described_class.from_env('ANTHROPIC_API_KEY' => 'chave')).to be_a(described_class)
    end

    # Devolver um objeto que falha na primeira chamada empurraria o erro para
    # longe da causa.
    it 'returns nil when no key is configured' do
      expect(described_class.from_env({})).to be_nil
    end

    it 'treats a blank key as no key' do
      expect(described_class.from_env('ANTHROPIC_API_KEY' => '   ')).to be_nil
    end

    it 'reads the model from the environment' do
      expect(described_class.from_env('ANTHROPIC_API_KEY' => 'k', 'AIAD_MODEL' => 'claude-opus-5').model)
        .to eq('claude-opus-5')
    end

    it 'has a default model' do
      expect(described_class.from_env('ANTHROPIC_API_KEY' => 'k').model).to eq(described_class::DEFAULT_MODEL)
    end
  end

  # Um dump de exceção não pode carregar credencial.
  describe 'a chave não vaza' do
    it 'keeps the key out of inspect' do
      expect(llm.inspect).not_to include('chave-de-teste')
    end

    it 'still says which model it is, which is what one wants to see' do
      expect(llm.inspect).to include('claude-sonnet-5')
    end
  end
end
