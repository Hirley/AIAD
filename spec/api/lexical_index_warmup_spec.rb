# frozen_string_literal: true

require 'json'
require 'stringio'

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
  # O log da partida vai para um StringIO na suíte, como no `build_spec`. Em
  # produção vai para a mesma saída padrão do log de requisição: um coletor só,
  # um formato só.
  let(:logs) { StringIO.new }
  let(:colecao) { 'documentos' }

  def warm(env = {})
    described_class.run(qdrant: qdrant, index: index, collection: colecao,
                        registry: registry, env: env, logs: logs)
    registry.render
  end

  def linha(env = {})
    warm(env)

    JSON.parse(logs.string.lines.last)
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

    # Ninguém olha painel durante um boot. Quem sobe o contêiner e vê a API
    # respondendo 200 lê o log, e é lá que o estado do índice precisa estar.
    it 'writes exactly one line per boot' do
      store('férias de trinta dias')
      warm

      expect(logs.string.lines.size).to eq(1)
    end

    it 'says how many chunks went in' do
      store('férias de trinta dias', 'reembolso de viagem')

      expect(linha).to include('documents' => 2, 'complete' => true)
    end

    # Índice completo não tem motivo, e a chave existe assim mesmo: esquema
    # estável é o que deixa `jq` e Loki filtrarem por motivo sem tratar a
    # ausência da chave como um caso à parte.
    it 'has no reason to give when nothing was cut short' do
      store('férias de trinta dias')

      expect(linha).to include('reason' => nil, 'level' => 'info', 'event' => 'lexical_index_warmup')
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

    # É esta informação que a métrica não carrega: o par `documents`/`complete`
    # diz que o índice ficou pela metade, e não qual dos três motivos o cortou.
    it 'names the chunk cap as the reason' do
      store('um', 'dois', 'três')

      expect(linha('AIAD_LEXICAL_INDEX_MAX' => '2'))
        .to include('reason' => 'max_documents', 'complete' => false, 'level' => 'warn')
    end
  end

  # O teto de tempo só é alcançável com mais trechos do que cabem numa página:
  # a página encolhe até o teto de trechos, então um acervo pequeno chega ao
  # fim antes de o relógio ter chance de opinar.
  describe 'teto de tempo' do
    it 'names the clock as the reason' do
      store(*Array.new(LexicalIndexLoader::PAGE + 1) { |i| "trecho número #{i}" })

      expect(linha('AIAD_LEXICAL_INDEX_TIMEOUT' => '0'))
        .to include('reason' => 'timeout', 'complete' => false, 'level' => 'warn')
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

    it 'writes the boot line anyway, saying there was nothing to load' do
      expect(linha).to include('documents' => 0, 'complete' => true, 'reason' => nil)
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

    it 'says in the log that the collection could not be read' do
      expect(linha).to include('reason' => 'unreachable', 'documents' => 0, 'level' => 'warn')
    end
  end

  # O `rescue StandardError` que estava aqui existia por um motivo bom — Qdrant
  # fora do ar na partida não pode derrubar a API — e engolia junto o que
  # precisa ser barulhento: defeito de programação. Um `NoMethodError` no meio
  # da varredura virava `documents 0` e `complete 0`, indistinguível de "o
  # Qdrant não respondeu", e o disfarce durava até alguém reparar que a busca
  # estava com um braço só.
  describe 'erro de programação no meio da varredura' do
    before do
      store('férias de trinta dias')
      allow(index).to receive(:add).and_raise(NoMethodError, "undefined method 'text' for nil")
    end

    it 'lets it through instead of degrading' do
      expect { warm }.to raise_error(NoMethodError)
    end

    it 'does not disguise itself as a collection it could not read' do
      expect { warm }.to raise_error(NoMethodError)

      expect(logs.string).to be_empty
    end
  end
end
