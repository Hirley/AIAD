# frozen_string_literal: true

require_relative '../bm25_index'
require_relative '../embedding_generator'
require_relative '../etl_pipeline'
require_relative '../http_qdrant_transport'
require_relative '../hybrid_retriever'
require_relative '../hyde_retriever'
require_relative '../parent_document_retriever'
require_relative '../qdrant_client'
require_relative 'lexical_index_warmup'

module Api
  # Monta o lado da busca: ETL, os dois índices da busca híbrida e os
  # decoradores de recuperação.
  #
  # Saiu do `Api.build` quando o Rubocop reclamou do tamanho do módulo, e a
  # reclamação estava certa — eram duas responsabilidades no mesmo arquivo. Lá
  # ficou o que a API **exige** de quem chega e como as rotas se compõem; aqui
  # está como o acervo é lido e escrito. Mudam por motivos diferentes.
  #
  # O ETL e o recuperador saem juntos porque nascem juntos: os dois índices que
  # a busca híbrida usa são alimentados por uma única ingestão, e separá-los só
  # criaria a chance de montar um sem o outro.
  #
  # O aquecimento do índice léxico acontece aqui, e não em quem chama, pelo
  # mesmo motivo: um índice que ninguém encheu é um recuperador montado pela
  # metade, e deixar isso a cargo de quem chama é deixar a chance de esquecer.
  module Retrieval
    def self.build(env:, llm:, options:, collection:, registry:)
      lexical_index = Bm25Index.new
      parent_store = ParentStore.new
      qdrant = QdrantClient.new(transport: HttpQdrantTransport.from_env(env))
      etl = etl_pipeline(qdrant, lexical_index, parent_store)

      LexicalIndexWarmup.run(qdrant: qdrant, index: lexical_index, collection: collection, registry: registry)

      { etl: etl, retriever: retriever_for(etl, lexical_index, parent_store, llm, options) }
    end

    # A busca híbrida é a base; documento pai e HyDE, quando ligados, envolvem o
    # recuperador por fora, cada um mantendo a mesma interface de busca.
    def self.retriever_for(etl, lexical_index, parent_store, llm, options)
      retriever = HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index)
      retriever = ParentDocumentRetriever.new(retriever: retriever, store: parent_store) if options[:parent_documents]

      options[:hyde] ? HydeRetriever.new(retriever: retriever, llm: llm) : retriever
    end
    private_class_method :retriever_for

    def self.etl_pipeline(qdrant, lexical_index, parent_store)
      EtlPipeline.new(
        qdrant: qdrant,
        embedder: EmbeddingGenerator.new,
        lexical_index: lexical_index,
        parent_store: parent_store
      )
    end
    private_class_method :etl_pipeline
  end
end
