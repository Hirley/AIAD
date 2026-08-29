# frozen_string_literal: true

require 'json'

require_relative '../../lib/api/app'
require_relative '../../lib/api/authentication'
require_relative '../../lib/conversation_memory'
require_relative '../../lib/conversation_store'
require_relative '../../lib/conversational_agent'
require_relative '../../lib/react_agent'
require_relative '../../lib/retrieval_tool'
require_relative '../../lib/tool_registry'
require_relative '../../spec/support/scripted_llm'

# O agente aqui é o de verdade — ReactAgent, ferramenta de busca e memória —
# com um modelo roteirizado no lugar do provedor. É o que permite exercitar a
# rota inteira sem chave e sem rede.
Dado('que a API do agente está no ar com as chaves:') do |table|
  @agent_keys = table.hashes.map { |row| "#{row['nome']}:#{row['chave']}:#{row['escopos']}" }.join(';')
  @agent_transport = InMemoryQdrantTransport.new
  @agent_lexical = Bm25Index.new
  @agent_etl = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: @agent_transport),
    embedder: EmbeddingGenerator.new(dimensions: 64),
    lexical_index: @agent_lexical
  )
  build_agent_api(nil)
end

Dado('que a API do agente está no ar sem modelo configurado') do
  build_agent_api(nil)
end

Dado('o acervo tem o documento {string} com {string}') do |source, content|
  @agent_etl.run(content, collection: API_COLLECTION, source: source)
end

Dado('que o modelo vai responder:') do |script|
  @agent_llm = ScriptedLlm.new(script.split(/^---$/).map(&:strip))
  build_agent_api(@agent_llm)
end

Quando('eu pergunto ao agente {string} com a chave {string}') do |question, key|
  post_json('/agent', { question: question }, key)
end

Quando('eu pergunto ao agente {string} na sessão {string} com a chave {string}') do |question, session, key|
  post_json('/agent', { question: question, session: session }, key)
end

Então('a resposta da API do agente deve ser {string}') do |answer|
  expect(json_response['answer']).to eq(answer)
end

Então('a resposta do agente deve dizer que usou a ferramenta {string}') do |tool|
  expect(json_response['tools']).to include(tool)
end

Então('a resposta do agente deve dizer que concluiu') do
  expect(json_response['finished']).to be(true)
end

Então('a resposta do agente não deve trazer o trajeto') do
  expect(json_response).not_to have_key('steps')
end

Então('a resposta do agente deve trazer uma sessão') do
  expect(json_response['session']).not_to be_empty
end

Então('a resposta do agente deve trazer a sessão {string}') do |session|
  expect(json_response['session']).to eq(session)
end

Então('o modelo deve ter recebido a pergunta anterior junto') do
  expect(@agent_llm.prompts.last).to include('quantos dias de férias')
end

Então('a resposta do agente deve dizer o que configurar') do
  expect(json_response['error']).to include('ANTHROPIC_API_KEY')
end

def build_agent_api(model)
  agent = agent_with(model)
  @app = Api::Authentication.new(
    Api::App.new(etl: @agent_etl, rag: agent_rag, collection: API_COLLECTION, agent: agent),
    store: ApiKeyStore.parse(@agent_keys)
  )
end

# Sem modelo, sem agente: é assim que a aplicação real se monta, e é o que faz
# a rota responder 503 dizendo o que falta.
def agent_with(model)
  return nil if model.nil?

  tools = ToolRegistry.new([RetrievalTool.build(retriever: @agent_etl, collection: API_COLLECTION)])

  ConversationalAgent.new(agent: ReactAgent.new(llm: model, tools: tools),
                          memory: ConversationMemory.new(store: ConversationStore.new))
end

# O `/ask` não é o assunto desta feature, mas a App exige um RAG: o extrativo
# serve, e deixa claro que a rota do agente não depende dele.
def agent_rag
  RagPipeline.new(retriever: @agent_etl, llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 2)
end
