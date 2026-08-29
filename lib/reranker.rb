# frozen_string_literal: true

require_relative 'stemmer'

# Re-ranking: reordena os candidatos que a recuperação trouxe, olhando o texto
# inteiro de cada trecho em vez de só a distância entre vetores.
#
# O scorer padrão mede cobertura léxica — quantos termos distintos da pergunta
# aparecem no trecho. É barato e já corrige o caso comum de um trecho vizinho
# ficar à frente do que realmente responde. Para re-ranking de verdade, injete
# um cross-encoder: `Reranker.new(scorer: ->(pergunta, texto) { ... })`.
class Reranker
  def initialize(scorer: nil)
    @scorer = scorer || method(:coverage)
  end

  def rerank(query, hits, limit: nil)
    scored = hits.each_with_index.map do |hit, position|
      hit.merge(rerank_score: score(query, text_of(hit)), original_position: position)
    end

    ordered = scored.sort_by { |hit| [-hit[:rerank_score], hit[:original_position]] }
                    .map { |hit| hit.except(:original_position) }

    limit ? ordered.first(limit) : ordered
  end

  private

  def score(query, text)
    @scorer.call(query, text).to_f
  end

  def text_of(hit)
    (hit[:payload] || {})[:text].to_s
  end

  def coverage(query, text)
    terms = Stemmer.stems(query).uniq
    return 0.0 if terms.empty? || text.empty?

    present = Stemmer.stems(text).to_set

    terms.count { |term| present.include?(term) }.fdiv(terms.size)
  end
end
