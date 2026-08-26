# frozen_string_literal: true

require_relative '../api_key_store'
require_relative '../bm25_index'
require_relative '../embedding_generator'
require_relative '../etl_pipeline'
require_relative '../extractive_llm'
require_relative '../http_qdrant_transport'
require_relative '../hybrid_retriever'
require_relative '../qdrant_client'
require_relative '../rag_pipeline'
require_relative 'app'
require_relative 'authentication'

module Api
  DEFAULT_COLLECTION = 'documentos'
  DEFAULT_TOP_K = 4

  # Monta a stack completa a partir do ambiente: transporte HTTP para o Qdrant,
  # ETL, busca híbrida, RAG e o middleware de controle de acesso por fora.
  #
  # Atenção ao índice léxico: ele é em memória e por processo. Isso basta para
  # rodar e para desenvolvimento, mas num deploy com vários workers cada um teria
  # o seu — o braço BM25 precisaria de um índice compartilhado (ou dos vetores
  # esparsos do próprio Qdrant) para valer em produção.
  def self.build(env: ENV)
    collection = collection_for(env)
    lexical_index = Bm25Index.new
    etl = etl_pipeline(env, lexical_index)

    rag = RagPipeline.new(
      retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
      llm: llm_for(env), collection: collection, top_k: top_k_for(env)
    )

    Authentication.new(App.new(etl: etl, rag: rag, collection: collection), store: ApiKeyStore.from_env(env))
  end

  def self.etl_pipeline(env, lexical_index)
    EtlPipeline.new(
      qdrant: QdrantClient.new(transport: HttpQdrantTransport.from_env(env)),
      embedder: EmbeddingGenerator.new,
      lexical_index: lexical_index
    )
  end
  private_class_method :etl_pipeline

  def self.collection_for(env = ENV)
    value = env['AIAD_COLLECTION'].to_s.strip

    value.empty? ? DEFAULT_COLLECTION : value
  end

  def self.top_k_for(env)
    Integer(env.fetch('AIAD_TOP_K', DEFAULT_TOP_K))
  end
  private_class_method :top_k_for

  # Sem modelo configurado a API responde de forma extrativa, recortando o
  # trecho recuperado em vez de gerar texto.
  def self.llm_for(_env)
    ExtractiveLlm.new
  end
  private_class_method :llm_for
end
