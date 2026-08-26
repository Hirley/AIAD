# frozen_string_literal: true

# Dublê de LLM: registra os prompts recebidos e devolve uma resposta fixa.
class FakeLlm
  attr_reader :prompts

  def initialize(response: 'Trinta dias por ano [1].')
    @response = response
    @prompts = []
  end

  def complete(prompt)
    @prompts << prompt
    @response
  end
end
