# frozen_string_literal: true

require_relative '../lib/hybrid_retriever'

RSpec.describe HybridRetriever do
  let(:vector_hits) do
    [
      { id: 1, score: 0.91, payload: { text: 'férias', source: 'politica.txt', autor: 'rh' } },
      { id: 2, score: 0.72, payload: { text: 'servidor', source: 'servidor.txt', autor: 'infra' } }
    ]
  end
  let(:vector_retriever) { FakeRetriever.new(results: vector_hits) }

  let(:lexical_index) do
    Bm25Index.new.tap do |index|
      index.add(2, 'reinicia o servidor de produção', payload: { text: 'servidor', source: 'servidor.txt',
                                                                 autor: 'infra' })
      index.add(3, 'erro ERR-4021 no cluster', payload: { text: 'erro', source: 'incidente.txt', autor: 'infra' })
    end
  end

  subject(:retriever) do
    described_class.new(vector_retriever: vector_retriever, lexical_index: lexical_index)
  end

  describe '#search' do
    it 'ranks first what both arms found' do
      result = retriever.search('servidor', collection: 'documentos')

      expect(result.first[:id]).to eq(2)
    end

    it 'reports which arms found each hit' do
      result = retriever.search('servidor', collection: 'documentos')

      expect(result.find { |hit| hit[:id] == 2 }[:matched_by]).to contain_exactly(:vector, :lexical)
      expect(result.find { |hit| hit[:id] == 1 }[:matched_by]).to eq([:vector])
    end

    it 'includes a hit found only by the lexical arm' do
      result = retriever.search('ERR-4021', collection: 'documentos')

      expect(result.map { |hit| hit[:id] }).to include(3)
    end

    it 'keeps the payload of each hit' do
      result = retriever.search('ERR-4021', collection: 'documentos')

      expect(result.find { |hit| hit[:id] == 3 }[:payload][:source]).to eq('incidente.txt')
    end

    it 'scores with reciprocal rank fusion' do
      result = retriever.search('servidor', collection: 'documentos')

      # id 2 é o 2º do braço vetorial e o 1º do léxico: 1/(60+2) + 1/(60+1)
      expect(result.first[:score]).to be_within(0.0001).of((1.0 / 62) + (1.0 / 61))
    end

    it 'respects the limit' do
      expect(retriever.search('servidor', collection: 'documentos', limit: 1).size).to eq(1)
    end

    it 'queries each arm with the candidate pool, not the final limit' do
      retriever.search('servidor', collection: 'documentos', limit: 1)

      expect(vector_retriever.calls.last[:limit]).to eq(described_class::DEFAULT_POOL)
    end

    it 'forwards the collection and the filter to the vector arm' do
      filter = { must: [{ key: 'autor', match: { value: 'infra' } }] }

      retriever.search('servidor', collection: 'documentos', filter: filter)

      expect(vector_retriever.calls.last).to include(collection: 'documentos', filter: filter)
    end

    it 'applies the metadata filter to the lexical arm as well' do
      filter = { must: [{ key: 'autor', match: { value: 'rh' } }] }

      result = retriever.search('ERR-4021', collection: 'documentos', filter: filter)

      expect(result.map { |hit| hit[:id] }).not_to include(3)
    end

    it 'returns an empty list when neither arm finds anything' do
      empty = described_class.new(vector_retriever: FakeRetriever.new(results: []), lexical_index: Bm25Index.new)

      expect(empty.search('nada', collection: 'documentos')).to be_empty
    end
  end
end
