# frozen_string_literal: true

require_relative '../../lib/cached_rag'
require_relative '../../lib/etl_pipeline'
require_relative '../../lib/hyde_retriever'
require_relative '../../lib/model_router'
require_relative '../../lib/parent_document_retriever'
require_relative '../../lib/rag_pipeline'
require_relative '../../lib/reranker'
require_relative '../../spec/support/fake_llm'
require_relative '../../spec/support/in_memory_qdrant_transport'

AVANCADO_COLLECTION = 'documentos'

def build_rag
  retriever = @retriever
  retriever = ParentDocumentRetriever.new(retriever: retriever, store: @parent_store) if @parent
  retriever = HydeRetriever.new(retriever: retriever, llm: @llm) if @hyde

  rag = RagPipeline.new(
    retriever: retriever, llm: @model, collection: AVANCADO_COLLECTION, top_k: 1,
    reranker: (Reranker.new if @rerank), compressor: (PromptCompressor.new if @budget),
    context_budget: @budget
  )

  @cache ? CachedRag.new(rag: rag, cache_factory: -> { SemanticCache.new(embedder: @embedder, threshold: 0.8) }) : rag
end

Dado('que o assistente avançado indexou os documentos:') do |table|
  @embedder = EmbeddingGenerator.new(dimensions: 64)
  @parent_store = ParentStore.new
  @retriever = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
    embedder: @embedder, parent_store: @parent_store
  )

  table.hashes.each do |row|
    @retriever.run(row['conteudo'], collection: AVANCADO_COLLECTION, source: row['origem'],
                                    metadata: { autor: row['autor'] })
  end

  @llm = FakeLlm.new(response: 'Trinta dias de férias por ano.')
  @model = @llm
end

Dado('que o re-ranking está ligado') do
  @rerank = true
end

Dado('a recuperação por documento pai está ligada') do
  @parent = true
end

Dado('que a recuperação por documento pai está ligada') do
  @parent = true
end

Dado('que o HyDE está ligado') do
  @hyde = true
end

Dado('que o orçamento de contexto é de {int} tokens') do |budget|
  @budget = budget
end

Dado('que o cache semântico está ligado') do
  @cache = true
end

Dado('que o roteamento de modelos está ligado') do
  @fast = FakeLlm.new(response: 'resposta do modelo barato')
  @strong = FakeLlm.new(response: 'resposta do modelo forte')
  @model = ModelRouter.new(fast: @fast, strong: @strong, threshold_tokens: 10_000)
end

Quando('eu pergunto ao assistente {string}') do |question|
  @rag ||= build_rag
  @answers ||= []
  @result = @rag.answer(question)
  @answers << @result
end

Então('a resposta deve vir de {string}') do |source|
  expect(@result[:sources]).to include(source)
end

Então('o contexto usado deve ser o documento inteiro de {string}') do |source|
  expect(@result[:passages].first[:text]).to eq(@parent_store.fetch(source))
end

Então('o modelo deve ter sido consultado para gerar a hipótese') do
  expect(@llm.prompts.first).to include('trecho de um documento interno')
end

Então('a resposta deve informar os tokens gastos no prompt e na geração') do
  expect(@result[:usage][:prompt_tokens]).to be_positive
  expect(@result[:usage][:completion_tokens]).to be_positive
end

Então('o contexto enviado deve caber em {int} tokens') do |budget|
  counter = TokenCounter.new
  expect(@result[:passages].sum { |passage| counter.estimate(passage[:text]) }).to be <= budget
end

Então('a segunda resposta deve ter vindo do cache') do
  expect(@answers.last[:cached]).to be(true)
end

Então('o modelo deve ter sido chamado apenas {int} vez') do |times|
  expect(@llm.prompts.size).to eq(times)
end

Então('a segunda resposta não deve ter gasto tokens') do
  expect(@answers.last[:usage][:total_tokens]).to eq(0)
end

Então('a pergunta deve ter sido atendida pelo modelo {string}') do |kind|
  expected = kind == 'barato' ? :fast : :strong
  expect(@model.last_choice).to eq(expected)
end
