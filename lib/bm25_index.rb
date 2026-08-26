# frozen_string_literal: true

require_relative 'tokenizer'

# Índice léxico BM25 em memória, usado no braço de busca por palavra-chave da
# busca híbrida.
#
# BM25 pontua um documento pela frequência dos termos da consulta, penalizando
# termos comuns (IDF) e documentos longos (normalização por tamanho) — pega
# exatamente o que o embedding costuma perder: nome de campo, código de erro,
# sigla, número de contrato.
class Bm25Index
  # Nomes canônicos do BM25: saturation é o k1 e length_normalization é o b.
  SATURATION = 1.5
  LENGTH_NORMALIZATION = 0.75

  def initialize(saturation: SATURATION, length_normalization: LENGTH_NORMALIZATION)
    @saturation = saturation
    @length_normalization = length_normalization
    @documents = {}
  end

  def add(id, text, payload: {})
    tokens = Tokenizer.tokens(text)
    @documents[id] = { frequencies: tokens.tally, length: tokens.size, payload: payload }
    self
  end

  def size
    @documents.size
  end

  def search(query, limit: 10)
    terms = Tokenizer.tokens(query)

    @documents.filter_map { |id, document| score_document(id, document, terms) }
              .sort_by { |hit| -hit[:score] }
              .first(limit)
  end

  private

  def score_document(id, document, terms)
    score = terms.sum { |term| term_score(document, term) }
    return nil if score <= 0

    { id: id, score: score, payload: document[:payload] }
  end

  def term_score(document, term)
    frequency = document[:frequencies].fetch(term, 0)
    return 0.0 if frequency.zero?

    normalization = 1 - @length_normalization + (@length_normalization * document[:length] / average_length)

    idf(term) * frequency * (@saturation + 1) / (frequency + (@saturation * normalization))
  end

  def idf(term)
    matching = @documents.count { |_, document| document[:frequencies].key?(term) }

    Math.log(1 + ((size - matching + 0.5) / (matching + 0.5)))
  end

  def average_length
    total = @documents.sum { |_, document| document[:length] }

    total.zero? ? 1.0 : total.fdiv(size)
  end
end
