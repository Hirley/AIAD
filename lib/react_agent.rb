# frozen_string_literal: true

require 'json'
require_relative 'react_parser'
require_relative 'tool_registry'
require_relative 'tracer'

# Agente ReAct: alterna raciocínio e ação até chegar na resposta.
#
# O laço é sempre o mesmo — o modelo escreve um pensamento e escolhe uma
# ferramenta, a ferramenta devolve uma observação, a observação volta para o
# prompt do turno seguinte — até ele escrever a resposta final.
#
# Três decisões que definem o comportamento:
#
# - **Teto de iterações.** Sem ele, um modelo teimoso chama ferramenta para
#   sempre, e cada volta é uma chamada paga. Batendo no teto o agente diz que
#   não concluiu, em vez de inventar uma resposta.
# - **Erro vira observação.** Ferramenta quebrada, argumento errado ou saída
#   ilegível voltam como texto para o modelo se corrigir no turno seguinte.
# - **O trajeto fica registrado.** `steps` guarda pensamento, ferramenta,
#   argumentos e observação de cada turno: sem isso não há como auditar por que
#   o agente respondeu o que respondeu.
class ReactAgent
  DEFAULT_MAX_ITERATIONS = 6
  NO_CONCLUSION = 'Não consegui concluir a resposta dentro do limite de passos.'
  FORMAT_HINT = 'Erro: não entendi o formato. Escreva "Ação:" com "Entrada:", ou "Resposta Final:".'
  JSON_FENCE = /\A```(?:json)?\s*(.*?)\s*```\z/m

  INSTRUCTION = <<~PROMPT
    Você é um agente que responde perguntas usando as ferramentas disponíveis.

    Ferramentas:
    %<catalog>s

    Siga exatamente este formato, um passo por vez:

    Pensamento: o que você precisa descobrir
    Ação: o nome de uma das ferramentas acima
    Entrada: os argumentos em JSON

    Depois de cada ação você recebe uma linha "Observação:" com o resultado.
    Nunca escreva a observação você mesmo — ela vem da ferramenta.

    Quando tiver a resposta, escreva:

    Pensamento: o que te levou à conclusão
    Resposta Final: a resposta para a pergunta

    Pergunta: %<question>s

    %<scratchpad>s
  PROMPT

  def initialize(llm:, tools:, max_iterations: DEFAULT_MAX_ITERATIONS, parser: ReactParser.new,
                 tracer: Tracer.null)
    @llm = llm
    @tools = tools
    @max_iterations = max_iterations
    @parser = parser
    @tracer = tracer
  end

  # A saída do trace é a resposta, não o hash interno: o trajeto e a contagem
  # de voltas já estão nos spans e nos metadados, e repetir tudo na saída só
  # entulharia o visualizador.
  def run(question)
    @tracer.trace('react.run', input: question, metadata: model_metadata) do |span|
      outcome = run_within(span, question)
      span.output = outcome[:answer]
      span.annotate(iterations: outcome[:iterations], finished: outcome[:finished])

      outcome
    end
  end

  private

  # Um agente pode dar várias voltas, cada uma custando uma chamada: sem o nome
  # do modelo no trace, o custo do agente somaria num balde "desconhecido"
  # junto com o do RAG.
  def model_metadata
    @llm.respond_to?(:model) ? { model: @llm.model } : {}
  end

  # O laço fica fora dos spans de propósito: sair de dentro de um span com
  # `return` fecharia ele sem saída registrada. Cada volta abre e fecha os seus.
  def run_within(span, question)
    steps = []

    (1..@max_iterations).each do |turn|
      step = think(span, question, steps, turn)
      return result(question, step[:answer], steps, turn) if step[:type] == :answer

      steps << act(span, step, turn)
    end

    result(question, NO_CONCLUSION, steps, @max_iterations, finished: false)
  end

  def think(span, question, steps, turn)
    prompt = prompt_for(question, steps)
    raw = span.span('react.llm', input: prompt, metadata: { turn: turn }) { @llm.complete(prompt) }

    @parser.parse(raw)
  end

  def act(span, step, turn)
    span.span('react.tool', input: step[:input], metadata: { turn: turn, tool: step[:tool] }) do |tool_span|
      executed = execute(step)
      tool_span.output = executed[:observation]

      executed
    end
  end

  def result(question, answer, steps, iterations, finished: true)
    { question: question, answer: answer, steps: steps, iterations: iterations, finished: finished }
  end

  def execute(step)
    return { thought: step[:thought], tool: nil, arguments: nil, observation: FORMAT_HINT } if step[:type] == :unknown

    arguments, error = arguments_for(@tools.fetch(step[:tool]), step[:input])
    observation = error || @tools.invoke(step[:tool], arguments)

    { thought: step[:thought], tool: step[:tool], arguments: arguments, observation: observation }
  end

  # Devolve [argumentos, nil] ou [nil, observação de erro].
  def arguments_for(tool, input)
    return [{}, nil] if input.nil? || tool.nil? || tool.parameters.empty?

    parsed = parse_json(input)
    return [parsed.transform_keys(&:to_sym), nil] if parsed.is_a?(Hash)

    wrap(tool, input)
  end

  # Modelo escreve texto solto o tempo todo. Com um parâmetro só não há dúvida
  # sobre onde ele vai; com mais de um, chutar seria pior do que pedir de novo.
  def wrap(tool, input)
    parameters = tool.parameters.keys
    return [{ parameters.first.to_sym => input }, nil] if parameters.size == 1

    [nil, "Erro: escreva a entrada de #{tool.name} em JSON com os campos #{parameters.join(', ')}."]
  end

  def parse_json(input)
    JSON.parse(input.to_s[JSON_FENCE, 1] || input.to_s)
  rescue JSON::ParserError
    nil
  end

  def prompt_for(question, steps)
    format(INSTRUCTION, catalog: @tools.catalog, question: question, scratchpad: scratchpad(steps))
  end

  def scratchpad(steps)
    steps.map { |step| transcript(step) }.join("\n\n")
  end

  def transcript(step)
    lines = ["Pensamento: #{step[:thought]}", "Ação: #{step[:tool]}"]
    lines << "Entrada: #{JSON.generate(step[:arguments])}" if step[:arguments]&.any?

    (lines << "Observação: #{step[:observation]}").join("\n")
  end
end
