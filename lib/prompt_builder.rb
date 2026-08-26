# frozen_string_literal: true

# Monta o prompt da etapa de geração do RAG: instrução, contexto recuperado
# (numerado e com a origem de cada trecho) e a pergunta do usuário.
#
# Numerar e identificar a origem permite que o modelo cite a fonte e que a
# resposta seja auditada depois.
class PromptBuilder
  class EmptyContextError < StandardError; end

  DEFAULT_INSTRUCTION = <<~TEXT.strip
    Responda à pergunta usando apenas os trechos de contexto abaixo.
    Se o contexto não contiver a resposta, diga que não sabe.
    Cite as origens usadas no formato [n].
  TEXT

  UNKNOWN_SOURCE = 'desconhecida'

  def initialize(instruction: DEFAULT_INSTRUCTION)
    @instruction = instruction
  end

  def build(question, passages)
    raise EmptyContextError, 'no passages to ground the answer' if passages.nil? || passages.empty?

    <<~PROMPT
      #{@instruction}

      Contexto:
      #{format_passages(passages)}

      Pergunta: #{question}
      Resposta:
    PROMPT
  end

  private

  def format_passages(passages)
    passages.each_with_index.map do |passage, index|
      "[#{index + 1}] (origem: #{passage[:source] || UNKNOWN_SOURCE})\n#{passage[:text]}"
    end.join("\n\n")
  end
end
