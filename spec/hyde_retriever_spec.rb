# frozen_string_literal: true

require_relative '../lib/hyde_retriever'

RSpec.describe HydeRetriever do
  let(:inner) { FakeRetriever.new(results: [{ id: 1, score: 0.9, payload: { text: 'trecho' } }]) }
  let(:llm) { FakeLlm.new(response: 'A política concede trinta dias de férias por ano.') }

  subject(:retriever) { described_class.new(retriever: inner, llm: llm) }

  describe '#search' do
    it 'asks the model for a hypothetical passage that answers the question' do
      retriever.search('quantos dias de férias', collection: 'documentos')

      expect(llm.prompts.last).to include('quantos dias de férias')
    end

    it 'searches with the hypothetical passage, not only with the question' do
      retriever.search('quantos dias de férias', collection: 'documentos')

      expect(inner.calls.last[:query]).to include('trinta dias de férias')
    end

    it 'keeps the original question in the query, so exact terms are not lost' do
      retriever.search('ERR-4021', collection: 'documentos')

      expect(inner.calls.last[:query]).to include('ERR-4021')
    end

    it 'returns what the inner retriever found' do
      expect(retriever.search('pergunta', collection: 'documentos').first[:id]).to eq(1)
    end

    it 'falls back to the plain question when the model answers nothing' do
      silent = described_class.new(retriever: inner, llm: FakeLlm.new(response: '  '))

      silent.search('quantos dias', collection: 'documentos')

      expect(inner.calls.last[:query]).to eq('quantos dias')
    end

    it 'forwards collection, limit and filter' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      retriever.search('pergunta', collection: 'documentos', limit: 3, filter: filter)

      expect(inner.calls.last).to include(collection: 'documentos', limit: 3, filter: filter)
    end
  end
end
