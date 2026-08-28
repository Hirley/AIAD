# frozen_string_literal: true

require_relative '../../lib/etl_pipeline'
require_relative '../../lib/react_agent'
require_relative '../../lib/retrieval_tool'
require_relative '../../spec/support/in_memory_qdrant_transport'
require_relative '../../spec/support/scripted_llm'

AGENT_COLLECTION = 'documentos'

# O agente só é montado na hora da pergunta: assim os passos anteriores podem
# trocar as ferramentas ou o limite de passos sem depender da ordem.
def build_agent
  ReactAgent.new(llm: @llm, tools: @tools, max_iterations: @max_iterations || ReactAgent::DEFAULT_MAX_ITERATIONS)
end

def first_tool_step
  @result[:steps].find { |step| step[:tool] }
end

Dado('que o agente tem acesso aos documentos:') do |table|
  etl = EtlPipeline.new(qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
                        embedder: EmbeddingGenerator.new(dimensions: 64))

  table.hashes.each { |row| etl.run(row['conteudo'], collection: AGENT_COLLECTION, source: row['origem']) }

  @tools = ToolRegistry.new([RetrievalTool.build(retriever: etl, collection: AGENT_COLLECTION, top_k: 1)])
end

Dado('que a busca nos documentos está fora do ar') do
  offline = Tool.new(name: RetrievalTool::NAME, description: RetrievalTool::DESCRIPTION,
                     parameters: RetrievalTool::PARAMETERS) { raise 'conexão recusada' }

  @tools = ToolRegistry.new([offline])
end

Dado('que o modelo responderá, em sequência:') do |script|
  @llm = ScriptedLlm.new(script.split(/^---$/).map(&:strip))
end

Dado('que o agente pode dar no máximo {int} passos') do |limit|
  @max_iterations = limit
end

Quando('eu peço ao agente {string}') do |question|
  @result = build_agent.run(question)
end

Então('a resposta do agente deve ser {string}') do |answer|
  expect(@result[:answer]).to eq(answer)
end

Então('o agente deve ter usado a ferramenta {string}') do |name|
  expect(@result[:steps].map { |step| step[:tool] }).to include(name)
end

Então('o agente não deve ter usado nenhuma ferramenta') do
  expect(@result[:steps]).to be_empty
end

Então('a observação da ferramenta deve conter {string}') do |text|
  expect(first_tool_step[:observation]).to include(text)
end

# Sem a defesa contra observação inventada, o texto que o modelo escreveu
# sozinho vaza para dentro do argumento e o agente busca outra coisa.
Então('o agente deve ter buscado exatamente {string}') do |termo|
  expect(first_tool_step[:arguments]).to eq(termo: termo)
end

Então('a observação da ferramenta deve citar a origem {string}') do |source|
  expect(first_tool_step[:observation]).to include(source)
end

Então('o agente deve informar que não concluiu') do
  expect(@result[:finished]).to be(false)
  expect(@result[:answer]).to eq(ReactAgent::NO_CONCLUSION)
end

Então('o agente deve ter feito {int} chamadas ao modelo') do |calls|
  expect(@llm.prompts.size).to eq(calls)
end
