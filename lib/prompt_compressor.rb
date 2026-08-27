# frozen_string_literal: true

require_relative 'token_counter'

# Compressão de prompt: encaixa o contexto recuperado num orçamento de tokens
# antes de chamar o modelo.
#
# Faz três coisas, da mais barata para a mais destrutiva: normaliza espaço em
# branco, descarta trecho repetido (pagar duas vezes pela mesma frase é o
# desperdício mais bobo) e, se ainda não couber, corta os menos relevantes.
# Nunca devolve contexto vazio: o último trecho é truncado em vez de sumir.
class PromptCompressor
  def initialize(counter: TokenCounter.new)
    @counter = counter
  end

  def compress(passages, budget:)
    compress_with_report(passages, budget: budget)[:passages]
  end

  def compress_with_report(passages, budget:)
    normalized = deduplicate(passages.map { |passage| normalize(passage) })
    kept = fit(normalized, budget)

    { passages: kept, dropped: normalized.size - kept.size,
      tokens_before: tokens_of(normalized), tokens_after: tokens_of(kept) }
  end

  private

  def normalize(passage)
    passage.merge(text: passage[:text].to_s.gsub(/\s+/, ' ').strip)
  end

  def deduplicate(passages)
    passages.uniq { |passage| passage[:text].downcase }
  end

  def fit(passages, budget)
    remaining = budget

    kept = passages.take_while do |passage|
      cost = @counter.estimate(passage[:text])
      remaining -= cost
      remaining >= 0
    end

    kept.empty? ? truncate_first(passages, budget) : kept
  end

  # Sem contexto nenhum a pergunta não tem como ser respondida, então o mais
  # relevante entra cortado no tamanho do orçamento.
  def truncate_first(passages, budget)
    first = passages.first
    return [] if first.nil? || budget <= 0

    text = fit_text(first[:text], budget)
    return [] if text.empty?

    [first.merge(text: text, truncated: true)]
  end

  # Corta palavra a palavra medindo o custo a cada passo: cortar por número de
  # caracteres não garante o orçamento, porque a estimativa também conta
  # palavras.
  def fit_text(text, budget)
    kept = []

    text.split.each do |word|
      candidate = kept + [word]
      break if @counter.estimate(candidate.join(' ')) > budget

      kept = candidate
    end

    kept.join(' ')
  end

  def tokens_of(passages)
    passages.sum { |passage| @counter.estimate(passage[:text]) }
  end
end
