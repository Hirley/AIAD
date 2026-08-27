# frozen_string_literal: true

require_relative 'tokenizer'

# Estimativa de tokens, para medir e limitar o que vai para o modelo antes de
# gastar a chamada.
#
# A heurística é a maior entre duas contas: ~4 caracteres por token e pelo menos um token
# por palavra. Texto com muita palavra curta ficaria subestimado só por
# caractere; texto com palavra longa, só por palavra. É estimativa, não
# tokenização — para o número exato de um provedor, injete o tokenizador dele:
# `TokenCounter.new(counter: ->(texto) { tiktoken.encode(texto).size })`.
class TokenCounter
  CHARS_PER_TOKEN = 4.0

  def initialize(counter: nil)
    @counter = counter
  end

  def estimate(text)
    value = text.to_s
    return 0 if value.empty?
    return @counter.call(value).to_i if @counter

    [by_characters(value), by_words(value), 1].max
  end

  def fits?(text, limit:)
    estimate(text) <= limit
  end

  private

  def by_characters(text)
    (text.length / CHARS_PER_TOKEN).ceil
  end

  # Toda palavra custa pelo menos um token, e palavra longa costuma ser
  # quebrada em vários.
  def by_words(text)
    Tokenizer.tokens(text).sum { |word| [(word.length / CHARS_PER_TOKEN).ceil, 1].max }
  end
end
