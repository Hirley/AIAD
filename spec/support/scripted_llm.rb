# frozen_string_literal: true

# Dublê de LLM com respostas em sequência, para exercitar um agente que chama o
# modelo várias vezes na mesma pergunta.
#
# Acabar o roteiro é erro, não resposta vazia: se o agente pedir mais turnos do
# que o cenário previu, isso aparece como falha clara em vez de laço infinito.
class ScriptedLlm
  class OutOfScriptError < StandardError; end

  attr_reader :prompts

  def initialize(*responses)
    @responses = responses.flatten
    @prompts = []
  end

  def complete(prompt)
    @prompts << prompt
    raise OutOfScriptError, "o agente pediu #{@prompts.size} respostas e o roteiro tem #{@responses.size}" if done?

    @responses[@prompts.size - 1]
  end

  def done?
    @prompts.size > @responses.size
  end
end
