# frozen_string_literal: true

require_relative '../../lib/plan_and_solve_agent'
require_relative '../../lib/react_agent'

# O agente só é montado na hora da pergunta, como no ReAct: assim os passos
# anteriores podem apertar o teto de passos ou o de chamadas ao modelo sem
# depender da ordem em que aparecem no cenário.
def build_planner_agent
  executor = ReactAgent.new(llm: @executor_llm, tools: @tools,
                            max_iterations: @max_iterations || ReactAgent::DEFAULT_MAX_ITERATIONS)

  PlanAndSolveAgent.new(llm: @planner_llm, executor: executor,
                        max_steps: @max_steps || PlanAndSolveAgent::DEFAULT_MAX_STEPS)
end

# O planejador e a síntese saem do mesmo modelo, em duas chamadas: primeiro o
# plano, depois a resposta final. O roteiro precisa das duas na ordem.
def script_planner
  @planner_llm = ScriptedLlm.new([@plan_response, @synthesis_response].compact)
end

def tool_calls_in(result)
  result[:steps].sum { |step| step[:trace].to_a.count { |turn| turn[:tool] } }
end

Dado('que o planejador responderá:') do |plan|
  @plan_response = plan
  script_planner
end

Dado('que a síntese do planejador será {string}') do |answer|
  @synthesis_response = answer
  script_planner
end

Dado('que o executor responderá, em sequência:') do |script|
  @executor_llm = ScriptedLlm.new(script.split(/^---$/).map(&:strip))
end

Dado('que o agente pode seguir no máximo {int} passos') do |limit|
  @max_steps = limit
end

Dado('que cada passo pode dar no máximo {int} chamada ao modelo') do |limit|
  @max_iterations = limit
end

Quando('eu peço ao agente planejador {string}') do |question|
  @result = build_planner_agent.run(question)
end

Então('o plano deve ter {int} passos') do |size|
  expect(@result[:plan].size).to eq(size)
end

Então('o plano deve ser a própria pergunta') do
  expect(@result[:plan]).to eq([@result[:question]])
end

Então('o agente deve ter consultado os documentos {int} vezes') do |calls|
  expect(tool_calls_in(@result)).to eq(calls)
end

Então('a tarefa do passo {int} deve conter {string}') do |number, text|
  expect(@executor_llm.prompts[number - 1]).to include(text)
end

Então('a tarefa do passo {int} não deve conter {string}') do |number, text|
  expect(@executor_llm.prompts[number - 1]).not_to include(text)
end

Então('o agente deve informar que um passo não concluiu') do
  expect(@result[:finished]).to be(false)
end

Então('o modelo deve ter visto que um passo não concluiu antes de responder') do
  expect(@planner_llm.prompts.last).to include(PlanAndSolveAgent::UNFINISHED_MARK)
end
