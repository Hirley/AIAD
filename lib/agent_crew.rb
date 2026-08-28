# frozen_string_literal: true

require_relative 'specialist_tool'
require_relative 'state_graph'
require_relative 'tool_registry'
require_relative 'tracer'

# Time de agentes especialistas com roteamento e revisão, montado sobre o
# `StateGraph`: rotear → executar → revisar, com a revisão podendo devolver o
# trabalho para o executor.
#
# É o ciclo que justifica o grafo. Numa lista de passos, "refazer com o que o
# revisor apontou" não tem como ser expresso: o fluxo só anda para a frente.
#
# Quatro decisões que definem o comportamento:
#
# - **Especialista é ferramenta.** O catálogo que o roteador lê, a validação de
#   argumentos e a conversão de falha em texto vêm do `ToolRegistry`, já
#   testados. Especialista que estoura vira texto de erro, não derruba o time.
# - **Nome inventado não para o time.** O roteador escrevendo um nome que não
#   existe cai no primeiro especialista, e a queda fica registrada em `routed`.
# - **A revisão volta com o motivo.** Refazer sem saber o que estava errado é
#   refazer igual, gastando outro agente inteiro.
# - **Teto de tentativas.** Revisor exigente sem teto refaz para sempre. No
#   teto, a resposta sai como está, marcada como não aprovada.
class AgentCrew
  DEFAULT_MAX_ATTEMPTS = 2

  # A revisão precisa começar com "aprovado" para valer como aprovação:
  # "não aprovado" contém a palavra, e procurar em qualquer lugar do texto
  # tomaria uma reprovação por aprovação.
  APPROVAL = /\A\W*aprovado\b/i

  ROUTING = <<~PROMPT
    Escolha quem deve responder à pergunta abaixo.

    Especialistas:
    %<catalog>s

    Responda apenas com o nome do especialista.

    Pergunta: %<question>s
  PROMPT

  TASK = <<~PROMPT
    %<question>s
    %<feedback>s
  PROMPT

  REWORK = <<~PROMPT

    Sua resposta anterior foi: %<answer>s
    A revisão apontou: %<feedback>s
    Refaça atendendo ao que foi apontado.
  PROMPT

  REVIEW = <<~PROMPT
    Revise a resposta abaixo para a pergunta do usuário.

    Se estiver correta e completa, responda exatamente: APROVADO
    Se não estiver, responda apenas o que precisa ser corrigido.

    Pergunta: %<question>s
    Resposta: %<answer>s
  PROMPT

  def initialize(llm:, specialists:, max_attempts: DEFAULT_MAX_ATTEMPTS, tracer: Tracer.null)
    @llm = llm
    @specialists = specialists
    @max_attempts = max_attempts
    @tracer = tracer
    @graph = build_graph
  end

  def run(question)
    walk = @graph.run(question: question, attempts: 0, reviews: [])

    result(walk)
  end

  private

  def result(walk)
    walk[:state].slice(:question, :specialist, :routed, :answer, :attempts, :approved, :reviews)
                .merge(path: walk[:path])
  end

  # Um passo para rotear e dois por tentativa (executar e revisar). O teto do
  # grafo é só a rede de segurança; quem encerra é o teto de tentativas.
  def build_graph
    StateGraph.new(max_steps: 1 + (2 * @max_attempts), name: 'crew.run', tracer: @tracer)
              .node(:rotear) { |state| route(state) }
              .node(:executar) { |state| execute(state) }
              .node(:revisar) { |state| review(state) }
              .edge(:rotear, :executar)
              .edge(:executar, :revisar)
              .branch(:revisar) { |state| done?(state) ? StateGraph::FINISH : :executar }
              .entry(:rotear)
  end

  def route(state)
    chosen = named_in(@llm.complete(format(ROUTING, catalog: @specialists.catalog, question: state[:question])))

    { specialist: chosen || @specialists.names.first, routed: !chosen.nil? }
  end

  def execute(state)
    task = format(TASK, question: state[:question], feedback: rework_note(state))
    answer = @specialists.invoke(state[:specialist], tarefa: task.strip)

    { answer: answer, attempts: state[:attempts] + 1 }
  end

  def review(state)
    verdict = @llm.complete(format(REVIEW, question: state[:question], answer: state[:answer]))

    { approved: verdict.match?(APPROVAL), feedback: verdict, reviews: state[:reviews] + [verdict] }
  end

  def done?(state)
    state[:approved] || state[:attempts] >= @max_attempts
  end

  def rework_note(state)
    return '' if state[:attempts].zero?

    format(REWORK, answer: state[:answer], feedback: state[:feedback])
  end

  # O modelo raramente responde só o nome; achar o nome dentro da frase custa
  # menos do que exigir um formato que ele não vai seguir.
  def named_in(text)
    @specialists.names.find { |name| text.to_s.match?(/\b#{Regexp.escape(name)}\b/i) }
  end
end
