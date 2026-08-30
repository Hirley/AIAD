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

      expect(loader.load).to eq(loaded: 2, complete: true, reason: nil)
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

      expect(loader.load).to eq(loaded: 5, complete: true, reason: nil)
    end
  end

  describe 'quando não há o que carregar' do
    it 'gives back zero for a collection that does not exist' do
      expect(loader.load).to eq(loaded: 0, complete: true, reason: nil)
    end

    it 'leaves the index empty instead of failing the boot' do
      loader.load

      expect(index.size).to eq(0)
    end

    it 'gives back zero for an empty collection' do
      qdrant.create_collection(colecao, vector_size: 4)

      expect(loader.load).to eq(loaded: 0, complete: true, reason: nil)
    end
  end

  # Trecho vazio entraria com tamanho zero e puxaria para baixo o tamanho médio
  # dos documentos, que é o que normaliza o score de todos os outros no BM25.
  describe 'ponto sem texto' do
    it 'does not count it' do
      qdrant.create_collection(colecao, vector_size: 4)
      qdrant.upsert_points(colecao, [{ id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { source: 'vazio.txt' } }])

      expect(loader.load).to eq(loaded: 0, complete: true, reason: nil)
    end

    it 'does not put it in the index either' do
      qdrant.create_collection(colecao, vector_size: 4)
      qdrant.upsert_points(colecao, [{ id: 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { text: '   ' } }])
      loader.load

      expect(index.size).to eq(0)
    end
  end

  # A varredura acontece antes de o Puma abrir a porta. Sem teto, o conserto do
  # índice teria trocado "sobe e busca pela metade" por "não sobe" num acervo
  # grande — e não subir derruba readiness probe e põe o contêiner em loop.
  describe 'teto de trechos' do
    subject(:loader) do
      described_class.new(qdrant: qdrant, index: index, collection: colecao, page: 2, max_documents: 3)
    end

    it 'stops at the cap instead of walking the whole collection' do
      store('um', 'dois', 'três', 'quatro', 'cinco')

      expect(loader.load).to eq(loaded: 3, complete: false, reason: :max_documents)
    end

    it 'says the index is complete when the collection fits under the cap' do
      store('um', 'dois')

      expect(loader.load).to eq(loaded: 2, complete: true, reason: nil)
    end

    # Os dois tetos podem estourar na mesma página, e aí o motivo teria de ser
    # escolhido no par ou no ímpar. O de trechos ganha por ser o determinístico:
    # ele depende do acervo, e vai estourar de novo no próximo boot. O de tempo
    # depende de como o Qdrant estava naquele minuto.
    it 'blames the cap, not the clock, when both trip on the same page' do
      # Prazo já vencido na primeira página **e** teto alcançado nela: se a
      # ordem das duas conferências se inverter, este exemplo passa a dizer
      # `:timeout`.
      loader = described_class.new(qdrant: qdrant, index: index, collection: colecao, page: 3,
                                   max_documents: 3, timeout: 0)
      store('um', 'dois', 'três', 'quatro', 'cinco')

      expect(loader.load).to eq(loaded: 3, complete: false, reason: :max_documents)
    end

    # Pedir a página cheia quando faltam poucos para o teto carregaria trechos
    # que a decisão já disse para não carregar.
    it 'shrinks the last page so it does not overshoot' do
      store('um', 'dois', 'três', 'quatro', 'cinco')
      loader.load

      expect(index.size).to eq(3)
    end
  end

  # O teto de tempo existe para o Qdrant lento: um acervo pequeno respondendo
  # devagar estouraria a espera sem nunca chegar perto do teto de trechos.
  describe 'teto de tempo' do
    subject(:loader) do
      described_class.new(qdrant: qdrant, index: index, collection: colecao, page: 1,
                          timeout: 5, clock: relogio)
    end

    # Anda cinco segundos a cada leitura: a primeira página passa, a segunda
    # encontra o prazo vencido.
    let(:relogio) do
      tempo = 0.0
      -> { tempo += 5.0 }
    end

    it 'stops when the deadline passes, keeping what it already indexed' do
      store('um', 'dois', 'três')

      expect(loader.load).to eq(loaded: 1, complete: false, reason: :timeout)
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
