# frozen_string_literal: true

require_relative '../../lib/agent_crew'
require_relative '../../lib/react_agent'

# O time só é montado na hora da pergunta: assim os passos anteriores podem
# declarar especialistas, roteamento, revisões e teto em qualquer ordem.
def build_crew
  specialists = @specialist_descriptions.map do |name, description|
    # Especialista declarado e não roteirizado é o que o cenário espera que
    # ninguém acione. Roteiro vazio estoura alto se ele for acionado, em vez
    # de derrubar a montagem de todo cenário que não usa os dois.
    agent = ReactAgent.new(llm: @specialist_scripts.fetch(name) { ScriptedLlm.new }, tools: @tools)

    SpecialistTool.build(name: name, description: description, agent: agent)
  end

  @crew_llm = ScriptedLlm.new([@route] + @reviews)
  AgentCrew.new(llm: @crew_llm, specialists: ToolRegistry.new(specialists),
                max_attempts: @max_attempts || AgentCrew::DEFAULT_MAX_ATTEMPTS)
end

Dado('que o time tem os especialistas:') do |table|
  @specialist_descriptions = table.hashes.to_h { |row| [row['nome'], row['descricao']] }
  @specialist_scripts = {}
  @reviews = []
end

Dado('que o roteador escolherá {string}') do |name|
  @route = name
end

Dado('que o especialista {string} responderá, em sequência:') do |name, script|
  @specialist_scripts[name] = ScriptedLlm.new(script.split(/^---$/).map(&:strip))
end

Dado('que a revisão dirá, em sequência:') do |script|
  @reviews = script.split(/^---$/).map(&:strip)
end

Dado('que o time pode fazer no máximo {int} tentativas') do |limit|
  @max_attempts = limit
end

Quando('eu peço ao time {string}') do |question|
  @result = build_crew.run(question)
end

Então('o time deve ter acionado o especialista {string}') do |name|
  expect(@result[:specialist]).to eq(name)
end

Então('a resposta do time deve ser {string}') do |answer|
  expect(@result[:answer]).to eq(answer)
end

Então('a resposta do time deve estar aprovada') do
  expect(@result[:approved]).to be(true)
end

Então('a resposta do time não deve estar aprovada') do
  expect(@result[:approved]).to be(false)
end

Então('o caminho do time deve ser {string}') do |path|
  expect(@result[:path].join(', ')).to eq(path)
end

Então('o time deve ter feito {int} tentativas') do |attempts|
  expect(@result[:attempts]).to eq(attempts)
end

Então('o time deve registrar que o roteamento falhou') do
  expect(@result[:routed]).to be(false)
end

Então('o especialista {string} deve ter recebido {string}') do |name, text|
  expect(@specialist_scripts.fetch(name).prompts.last).to include(text)
end
