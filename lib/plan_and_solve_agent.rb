# frozen_string_literal: true

require_relative 'plan_parser'
require_relative 'tracer'

# Agente Plan-and-Solve: primeiro escreve o plano inteiro, depois executa passo
# a passo e por fim junta tudo numa resposta.
#
# É o contraponto do ReAct, que decide o próximo passo olhando só o anterior.
# Decidir tudo de uma vez tem uma vantagem concreta: numa pergunta que precisa
# de várias apurações, o ReAct tende a responder assim que a primeira busca
# parece suficiente. Aqui o plano existe antes da primeira observação, então o
# agente não abandona no meio o que ele mesmo disse que ia fazer.
#
# Quatro decisões que definem o comportamento:
#
# - **Teto de passos.** O plano é escrito por um modelo, e modelo escreve plano
#   de vinte passos sem pestanejar. Cada passo é uma execução inteira, com as
#   chamadas de modelo dela. O teto é o que separa isso de uma conta surpresa.
# - **Plano ilegível não derruba a corrida.** Prosa em vez de lista vira um
#   plano de um passo só: a própria pergunta.
# - **Cada passo vê o que já foi apurado.** Sem isso, um passo que depende do
#   anterior recomeça do zero e o plano deixa de ser plano.
# - **Passo que não concluiu chega marcado na síntese.** Se resultado bom e
#   resultado faltando chegam iguais ao modelo, ele preenche a lacuna com
#   invenção. Marcado, ele diz o que ficou de fora.
#
# - **O trajeto de cada passo fica guardado.** O executor devolve o que fez
#   dentro do passo, e isso vai junto no resultado: sem o trajeto não há como
#   auditar por que o agente respondeu o que respondeu.
#
# O executor é injetado: normalmente um `ReactAgent`, mas qualquer objeto que
# responda a `run(tarefa)` devolvendo `answer:` e `finished:` serve.
class PlanAndSolveAgent
  DEFAULT_MAX_STEPS = 5
  UNFINISHED_MARK = '(não concluído)'

  PLANNING = <<~PROMPT
    Divida a pergunta abaixo em um plano curto de no máximo %<limit>d passos.

    Escreva um passo por linha, numerados, e nada além da lista. Cada passo
    precisa ser executável sozinho por quem só tem a pergunta e os passos
    anteriores em mãos. Se a pergunta se resolve num passo só, escreva um só.

    Pergunta: %<question>s
  PROMPT

  TASK = <<~PROMPT
    Pergunta original: %<question>s

    %<found>s
    Sua tarefa agora: %<task>s
  PROMPT

  SYNTHESIS = <<~PROMPT.freeze
    Responda à pergunta usando o que foi apurado nos passos abaixo.

    Passos marcados com "#{UNFINISHED_MARK}" não chegaram a uma conclusão: não
    complete a lacuna por conta própria, diga o que ficou faltando.

    Pergunta: %<question>s

    Apurado:
    %<found>s

    Resposta:
  PROMPT

  def initialize(llm:, executor:, max_steps: DEFAULT_MAX_STEPS, parser: PlanParser.new, tracer: Tracer.null)
    @llm = llm
    @executor = executor
    @max_steps = max_steps
    @parser = parser
    @tracer = tracer
  end

  def run(question)
    @tracer.trace('plan_and_solve.run', input: question) { |span| run_within(span, question) }
  end

  private

  def run_within(span, question)
    plan = plan_for(span, question)
    steps = solve(span, question, plan)
    answer = answer_for(span, question, steps)
    span.output = answer

    { question: question, plan: plan, steps: steps, answer: answer,
      finished: steps.all? { |step| step[:finished] } }
  end

  def plan_for(span, question)
    span.span('plan_and_solve.plan', input: question) do |planning|
      plan = @parser.parse(@llm.complete(format(PLANNING, question: question, limit: @max_steps)))
      plan = [question] if plan.empty?

      planning.output = plan.first(@max_steps)
    end
  end

  def solve(span, question, plan)
    plan.each_with_object([]).with_index(1) do |(task, steps), number|
      steps << solve_step(span, question, task, steps, number)
    end
  end

  def solve_step(span, question, task, steps, number)
    span.span('plan_and_solve.step', input: task, metadata: { step: number }) do |step_span|
      result = @executor.run(format(TASK, question: question, task: task, found: found_so_far(steps)))
      step_span.output = result[:answer]
      step_span.annotate(step: number, finished: result[:finished])

      { task: task, answer: result[:answer], finished: result[:finished], trace: result[:steps] }
    end
  end

  def answer_for(span, question, steps)
    span.span('plan_and_solve.synthesis') do
      @llm.complete(format(SYNTHESIS, question: question, found: transcript(steps)))
    end
  end

  # No primeiro passo não há nada apurado, e anunciar uma seção vazia só
  # convida o modelo a inventar o que deveria estar nela.
  def found_so_far(steps)
    return '' if steps.empty?

    "O que já foi apurado:\n#{transcript(steps)}\n"
  end

  def transcript(steps)
    steps.each_with_index.map { |step, index| line(step, index) }.join("\n")
  end

  def line(step, index)
    mark = step[:finished] ? '' : " #{UNFINISHED_MARK}"

    "#{index + 1}. #{step[:task]}#{mark} → #{step[:answer]}"
  end
end
