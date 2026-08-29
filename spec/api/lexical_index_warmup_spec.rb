# frozen_string_literal: true

require_relative '../../lib/api/lexical_index_warmup'
require_relative '../../lib/bm25_index'
require_relative '../../lib/metric_registry'
require_relative '../../lib/qdrant_client'
require_relative '../support/in_memory_qdrant_transport'

RSpec.describe Api::LexicalIndexWarmup do
  let(:transport) { InMemoryQdrantTransport.new }
  let(:qdrant) { QdrantClient.new(transport: transport) }
  let(:index) { Bm25Index.new }
  let(:registry) { MetricRegistry.new }
  let(:colecao) { 'documentos' }

  def warm(env = {})
    described_class.run(qdrant: qdrant, index: index, collection: colecao, registry: registry, env: env)
    registry.render
  end

  def store(*textos)
    qdrant.create_collection(colecao, vector_size: 4)
    pontos = textos.each_with_index.map do |texto, i|
      { id: i + 1, vector: [0.1, 0.2, 0.3, 0.4], payload: { text: texto, source: "doc-#{i + 1}.txt" } }
    end

    qdrant.upsert_points(colecao, pontos)
  end

  describe 'acervo que cabe' do
    it 'publishes how many chunks went in' do
      store('férias de trinta dias', 'reembolso de viagem')

      expect(warm).to include("aiad_lexical_index_documents 2\n")
    end

    it 'says the index covers the whole collection' do
      store('férias de trinta dias')

      expect(warm).to include("aiad_lexical_index_complete 1\n")
    end
  end

  # Índice parcial é melhor que índice nenhum, e muito melhor que não subir.
  # O que não pode é a diferença não aparecer: 2 trechos com o acervo inteiro
  # e 2 trechos por ter parado no teto são situações diferentes, e só a segunda
  # métrica as separa.
  describe 'acervo maior que o teto' do
    it 'still publishes what it managed to load' do
      store('um', 'dois', 'três')

      expect(warm('AIAD_LEXICAL_INDEX_MAX' => '2')).to include("aiad_lexical_index_documents 2\n")
    end

    it 'says the index is partial' do
      store('um', 'dois', 'três')

      expect(warm('AIAD_LEXICAL_INDEX_MAX' => '2')).to include("aiad_lexical_index_complete 0\n")
    end
  end

  describe 'acervo vazio' do
    it 'reports zero chunks' do
      expect(warm).to include("aiad_lexical_index_documents 0\n")
    end

    # Zero trecho de um acervo vazio é um índice **completo**: não há nada
    # faltando. É o que distingue "não há documento" de "não consegui ler".
    it 'reports the empty index as complete' do
      expect(warm).to include("aiad_lexical_index_complete 1\n")
    end
  end

  describe 'Qdrant fora do ar' do
    before { allow(transport).to receive(:get).and_return({ ok: false }) }

    it 'does not blow up the boot' do
      expect { warm }.not_to raise_error
    end

    it 'reports zero chunks' do
      expect(warm).to include("aiad_lexical_index_documents 0\n")
    end

    # Aqui é onde as duas métricas se pagam: zero trechos com `complete 0`
    # significa "não consegui ler o acervo", e não "o acervo está vazio".
    it 'reports the index as incomplete, unlike an empty collection' do
      expect(warm).to include("aiad_lexical_index_complete 0\n")
    end
  end
end
