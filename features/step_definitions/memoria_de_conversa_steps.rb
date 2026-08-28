# frozen_string_literal: true

require 'tmpdir'
require_relative '../../lib/conversational_agent'
require_relative '../../lib/file_conversation_store'
require_relative '../../lib/react_agent'

# O assistente é montado uma vez e reaproveitado entre as perguntas: é o que
# faz a memória valer alguma coisa. O cenário de reinício monta outro por cima
# do mesmo store, que é justamente o que se quer provar.
def assistant
  @assistant ||= build_assistant
end

def build_assistant
  @memory = ConversationMemory.new(store: @store || ConversationStore.new,
                                   budget: @budget || ConversationMemory::DEFAULT_BUDGET)

  ConversationalAgent.new(agent: ReactAgent.new(llm: @llm, tools: @tools), memory: @memory)
end

After { FileUtils.remove_entry(@conversation_directory) if @conversation_directory }

Dado('que a conversa é guardada em disco') do
  @conversation_directory = Dir.mktmpdir
  @store = FileConversationStore.new(@conversation_directory)
end

Dado('que o histórico cabe em {int} tokens') do |budget|
  @budget = budget
end

Quando('eu pergunto na conversa {string} {string}') do |conversation, question|
  @result = assistant.ask(conversation, question)
end

Quando('o assistente é reiniciado do zero') do
  @assistant = nil
end

Então('o agente deve ter visto {string} na última pergunta') do |text|
  expect(@llm.prompts.last).to include(text)
end

Então('o agente não deve ter visto {string} na última pergunta') do |text|
  expect(@llm.prompts.last).not_to include(text)
end

Então('o agente não deve ter visto nenhum histórico na última pergunta') do
  expect(@llm.prompts.last).not_to include(ConversationalAgent::HISTORY_HEADING)
end

Então('a resposta da conversa deve ser {string}') do |answer|
  expect(@result[:answer]).to eq(answer)
end

Então('a conversa {string} deve ter {int} turnos guardados') do |conversation, turns|
  expect(@memory.turns(conversation).size).to eq(turns)
end
