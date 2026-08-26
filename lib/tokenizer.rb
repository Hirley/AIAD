# frozen_string_literal: true

# Tokenização compartilhada pelos dois braços da busca híbrida: o vetorial
# (EmbeddingGenerator) e o léxico (Bm25Index). Manter uma única regra evita que
# os dois discordem sobre o que é um termo.
module Tokenizer
  PATTERN = /[[:alnum:]]+/

  def self.tokens(text)
    text.to_s.downcase.scan(PATTERN)
  end
end
