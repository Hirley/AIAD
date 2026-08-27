# frozen_string_literal: true

require_relative '../lib/parent_document_retriever'

RSpec.describe ParentDocumentRetriever do
  let(:store) do
    ParentStore.new.tap do |parent_store|
      parent_store.put('politica.txt', 'Documento inteiro da política, com muito mais contexto ao redor.')
    end
  end
  let(:child_hits) do
    [
      { id: 1, score: 0.9, payload: { text: 'trinta dias', source: 'politica.txt',
                                      parent_id: 'politica.txt', autor: 'rh' } },
      { id: 2, score: 0.7, payload: { text: 'três períodos', source: 'politica.txt',
                                      parent_id: 'politica.txt', autor: 'rh' } },
      { id: 3, score: 0.5, payload: { text: 'órfão', source: 'sumido.txt', parent_id: 'sumido.txt' } }
    ]
  end
  let(:inner) { FakeRetriever.new(results: child_hits) }

  subject(:retriever) { described_class.new(retriever: inner, store: store) }

  describe '#search' do
    it 'answers with the parent text instead of the chunk that matched' do
      result = retriever.search('férias', collection: 'documentos')

      expect(result.first[:payload][:text]).to eq(store.fetch('politica.txt'))
    end

    it 'collapses chunks of the same document into one result' do
      result = retriever.search('férias', collection: 'documentos')

      expect(result.count { |hit| hit[:payload][:source] == 'politica.txt' }).to eq(1)
    end

    it 'keeps the best score among the chunks of the document' do
      result = retriever.search('férias', collection: 'documentos')

      expect(result.first[:score]).to eq(0.9)
    end

    it 'keeps the other metadata of the chunk' do
      result = retriever.search('férias', collection: 'documentos')

      expect(result.first[:payload][:autor]).to eq('rh')
    end

    it 'falls back to the chunk text when the parent is unknown' do
      result = retriever.search('férias', collection: 'documentos')

      expect(result.map { |hit| hit[:payload][:text] }).to include('órfão')
    end

    it 'asks the inner retriever for more chunks than the limit, since dedup shrinks the list' do
      retriever.search('férias', collection: 'documentos', limit: 2)

      expect(inner.calls.last[:limit]).to be > 2
    end

    it 'respects the limit after collapsing' do
      expect(retriever.search('férias', collection: 'documentos', limit: 1).size).to eq(1)
    end

    it 'forwards collection and filter to the inner retriever' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      retriever.search('férias', collection: 'documentos', filter: filter)

      expect(inner.calls.last).to include(collection: 'documentos', filter: filter)
    end
  end
end
