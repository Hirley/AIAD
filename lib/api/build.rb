# frozen_string_literal: true

require_relative '../anthropic_llm'
require_relative '../api_key_store'
require_relative '../bm25_index'
require_relative '../cached_rag'
require_relative '../conversation_memory'
require_relative '../conversation_store'
require_relative '../conversational_agent'
require_relative '../embedding_generator'
require_relative '../etl_pipeline'
require_relative '../evaluated_rag'
require_relative '../extractive_llm'
require_relative '../http_qdrant_transport'
require_relative '../hybrid_retriever'
require_relative '../hyde_retriever'
require_relative '../parent_document_retriever'
require_relative '../prometheus_evaluation_log'
require_relative '../prometheus_trace_exporter'
require_relative '../prompt_compressor'
require_relative '../qdrant_client'
require_relative '../rag_pipeline'
require_relative '../react_agent'
require_relative '../reranker'
require_relative '../retrieval_tool'
require_relative '../semantic_cache'
require_relative '../tool_registry'
require_relative '../tracer'
require_relative 'app'
require_relative 'authentication'
require_relative 'metrics_endpoint'
require_relative 'observability'

module Api
  DEFAULT_COLLECTION = 'documentos'
  DEFAULT_TOP_K = 4
  DEFAULT_CONTEXT_BUDGET = 1500
  DEFAULT_HISTORY_BUDGET = ConversationMemory::DEFAULT_BUDGET
  DEFAULT_MAX_SESSIONS = ConversationStore::DEFAULT_MAX_SESSIONS
  TRUE_VALUES = %w[1 true yes on].freeze

  # Monta a stack completa a partir do ambiente: transporte HTTP para o Qdrant,
  # ETL, busca híbrida, RAG e o middleware de controle de acesso por fora.
  #
  # Atenção ao índice léxico: ele é em memória e por processo. Isso basta para
  # rodar e para desenvolvimento, mas num deploy com vários workers cada um teria
  # o seu — o braço BM25 precisaria de um índice compartilhado (ou dos vetores
  # esparsos do próprio Qdrant) para valer em produção.
  def self.build(env: ENV, registry: Observability.registry, logs: $stdout)
    app = MetricsEndpoint.new(application_for(env, registry), registry: registry)

    Observability.wrap(Authentication.new(app, store: ApiKeyStore.from_env(env)), registry: registry, logs: logs)
  end

  # A aplicação e os middlewares se montam separados de propósito: aqui é o que
  # a API **faz**, e no `build` é o que ela **exige** de quem chega. Misturar os
  # dois foi ficando ilegível conforme a pilha cresceu.
  def self.application_for(env, registry)
    collection = collection_for(env)
    options = retrieval_options(env)
    llm = llm_for(env)
    etl, retriever = retrieval_for(env, llm, options)

    App.new(etl: etl, collection: collection,
            rag: rag_pipeline(retriever, llm, collection, options, registry),
            agent: agent_for(retriever, collection, registry, env))
  end
  private_class_method :application_for

  # O ETL e o recuperador saem juntos porque nascem juntos: os dois índices que
  # a busca híbrida usa são alimentados por uma única ingestão, e separá-los
  # aqui só criaria a chance de montar um sem o outro.
  def self.retrieval_for(env, llm, options)
    lexical_index = Bm25Index.new
    parent_store = ParentStore.new
    etl = etl_pipeline(env, lexical_index, parent_store)

    [etl, retriever_for(etl, lexical_index, parent_store, llm, options)]
  end
  private_class_method :retrieval_for

  # Ligados por padrão: re-ranking e cache semântico, que melhoram a resposta
  # sem chamada extra ao modelo. Desligados por padrão: HyDE, que gasta uma
  # chamada a mais por pergunta, e documento pai, que muda bastante o tamanho
  # do contexto.
  def self.retrieval_options(env = ENV)
    {
      rerank: flag(env, 'AIAD_RERANK', default: true),
      cache: flag(env, 'AIAD_CACHE', default: true),
      hyde: flag(env, 'AIAD_HYDE', default: false),
      parent_documents: flag(env, 'AIAD_PARENT_DOCUMENTS', default: false),
      evaluate: flag(env, 'AIAD_EVALUATE', default: true),
      context_budget: Integer(env.fetch('AIAD_CONTEXT_BUDGET', DEFAULT_CONTEXT_BUDGET))
    }
  end

  def self.flag(env, name, default:)
    value = env[name]
    return default if value.nil? || value.to_s.strip.empty?

    TRUE_VALUES.include?(value.to_s.strip.downcase)
  end
  private_class_method :flag

  # A busca híbrida é a base; documento pai e HyDE, quando ligados, envolvem o
  # recuperador por fora, cada um mantendo a mesma interface de busca.
  def self.retriever_for(etl, lexical_index, parent_store, llm, options)
    retriever = HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index)
    retriever = ParentDocumentRetriever.new(retriever: retriever, store: parent_store) if options[:parent_documents]

    options[:hyde] ? HydeRetriever.new(retriever: retriever, llm: llm) : retriever
  end
  private_class_method :retriever_for

  # A ordem dos decoradores importa. A avaliação fica **por dentro** do cache:
  # resposta servida do cache já foi avaliada quando entrou, e pontuá-la de novo
  # gastaria CPU para chegar na mesma nota e contaria a mesma resposta duas
  # vezes no histograma — inflando a média com repetição em vez de medir
  # respostas novas.
  def self.rag_pipeline(retriever, llm, collection, options, registry)
    rag = RagPipeline.new(
      retriever: retriever, llm: llm, collection: collection, top_k: DEFAULT_TOP_K,
      reranker: (Reranker.new if options[:rerank]),
      compressor: PromptCompressor.new, context_budget: options[:context_budget],
      tracer: Tracer.new(exporter: PrometheusTraceExporter.new(registry: registry))
    )
    rag = EvaluatedRag.new(rag: rag, log: PrometheusEvaluationLog.new(registry: registry)) if options[:evaluate]

    options[:cache] ? CachedRag.new(rag: rag) : rag
  end
  private_class_method :rag_pipeline

  # O agente só existe quando há modelo de verdade. O `ExtractiveLlm` recorta
  # trecho, não escreve "Pensamento / Ação / Resposta Final": montar o ReAct em
  # cima dele daria seis voltas no laço para devolver "não cheguei a uma
  # conclusão". `nil` aqui faz a rota responder 503 dizendo o que configurar,
  # que é uma falha imediata e explicada.
  #
  # A memória é por processo, como o índice BM25 e o cache semântico. Vale para
  # um worker; com mais de um, a conversa dependeria de qual deles atendeu.
  def self.agent_for(retriever, collection, registry, env)
    model = AnthropicLlm.from_env(env)
    return nil if model.nil?

    tools = ToolRegistry.new([RetrievalTool.build(retriever: retriever, collection: collection)])
    tracer = Tracer.new(exporter: PrometheusTraceExporter.new(registry: registry))

    ConversationalAgent.new(agent: ReactAgent.new(llm: model, tools: tools, tracer: tracer),
                            memory: memory_for(env))
  end
  private_class_method :agent_for

  # Dois tetos, medindo coisas diferentes. O orçamento é sobre o **custo de
  # cada pergunta**: o histórico inteiro vai no prompt toda vez. O número de
  # sessões é sobre a **memória do processo**: sem teto, uma sessão nova por
  # pergunta enche o Hash até o processo morrer, e o vazamento só apareceria
  # semanas depois sem nada apontando para a causa.
  def self.memory_for(env)
    ConversationMemory.new(
      store: ConversationStore.new(max_sessions: Integer(env.fetch('AIAD_MAX_SESSIONS', DEFAULT_MAX_SESSIONS))),
      budget: Integer(env.fetch('AIAD_HISTORY_BUDGET', DEFAULT_HISTORY_BUDGET))
    )
  end
  private_class_method :memory_for

  def self.etl_pipeline(env, lexical_index, parent_store)
    EtlPipeline.new(
      qdrant: QdrantClient.new(transport: HttpQdrantTransport.from_env(env)),
      embedder: EmbeddingGenerator.new,
      lexical_index: lexical_index,
      parent_store: parent_store
    )
  end
  private_class_method :etl_pipeline

  def self.collection_for(env = ENV)
    value = env['AIAD_COLLECTION'].to_s.strip

    value.empty? ? DEFAULT_COLLECTION : value
  end

  # Com `ANTHROPIC_API_KEY` no ambiente, o modelo de verdade. Sem ela, a API
  # continua respondendo de forma extrativa, recortando o trecho recuperado em
  # vez de gerar texto — que é o que permite rodar a stack inteira sem
  # credencial de provedor.
  def self.llm_for(env)
    AnthropicLlm.from_env(env) || ExtractiveLlm.new
  end
  private_class_method :llm_for
end
