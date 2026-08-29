# frozen_string_literal: true

require_relative '../lib/bm25_index'
require_relative '../lib/lexical_index_loader'
require_relative '../lib/qdrant_client'
require_relative 'support/in_memory_qdrant_transport'

RSpec.describe LexicalIndexLoader do
  subject(:loader) { described_class.new(qdrant: qdrant, index: index, collection: colecao, page: 2) }

  let(:transport) { InMemoryQdrantTransport.new }
  let(:qdrant) { QdrantClient.new(transport: transport) }
  let(:index) { Bm25Index.new }
  let(:colecao) { 'documentos' }

  def store(*textos)
    qdrant.create_collection(colecao, vector_size: 4)
    pontos = textos.each_with_index.map do |texto, i|
      { id: i + 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { text: texto, source: "doc-#{i + 1}.txt" } }
    end

    qdrant.upsert_points(colecao, pontos)
  end

  describe 'reconstruindo o índice' do
    it 'gives back how many chunks it indexed' do
      store('férias de trinta dias', 'reembolso de viagem')

      expect(loader.load).to eq(2)
    end

    it 'fills the index, so the lexical arm searches again' do
      store('a política de férias garante trinta dias corridos')
      loader.load

      expect(index.search('férias').map { |hit| hit[:id] }).to eq([1])
    end

    it 'carries the payload along, or the filter by source stops working' do
      store('reembolso de viagem cobre hospedagem')
      loader.load

      expect(index.search('reembolso').first[:payload][:source]).to eq('doc-1.txt')
    end

    # A página é 2 e há 5 trechos: sem o laço, o índice ficaria com os dois
    # primeiros e a busca perderia o resto em silêncio.
    it 'walks every page, not just the first' do
      store('um', 'dois', 'três', 'quatro', 'cinco')

      expect(loader.load).to eq(5)
    end
  end

  describe 'quando não há o que carregar' do
    it 'gives back zero for a collection that does not exist' do
      expect(loader.load).to eq(0)
    end

    it 'leaves the index empty instead of failing the boot' do
      loader.load

      expect(index.size).to eq(0)
    end

    it 'gives back zero for an empty collection' do
      qdrant.create_collection(colecao, vector_size: 4)

      expect(loader.load).to eq(0)
    end
  end

  # Trecho vazio entraria com tamanho zero e puxaria para baixo o tamanho médio
  # dos documentos, que é o que normaliza o score de todos os outros no BM25.
  describe 'ponto sem texto' do
    it 'does not count it' do
      qdrant.create_collection(colecao, vector_size: 4)
      qdrant.upsert_points(colecao, [{ id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { source: 'vazio.txt' } }])

      expect(loader.load).to eq(0)
    end

    it 'does not put it in the index either' do
      qdrant.create_collection(colecao, vector_size: 4)
      qdrant.upsert_points(colecao, [{ id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { text: '   ' } }])
      loader.load

      expect(index.size).to eq(0)
    end
  end

  # Política de degradação não mora aqui: quem monta a aplicação é que decide o
  # que fazer com o Qdrant fora do ar, e decide no `Api.build`.
  describe 'quando o Qdrant falha' do
    it 'lets the error through' do
      allow(transport).to receive(:get).and_return({ ok: false })

      expect { loader.load }.to raise_error(QdrantClient::RequestError)
    end
  end
end
