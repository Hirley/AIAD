# frozen_string_literal: true

# Tokenização compartilhada pelos dois braços da busca híbrida: o vetorial
# (EmbeddingGenerator) e o léxico (Bm25Index). Manter uma única regra evita que
# os dois discordem sobre o que é um termo.
module Tokenizer
  PATTERN = /[[:alnum:]]+/

  # Lista curta de propósito: só as palavras funcionais mais comuns do
  # português. Lista grande começa a derrubar termo que importa.
  #
  # As interrogativas estão aqui por um motivo específico: "quantos", "quando",
  # "qual" nunca aparecem na resposta, e sem tirá-las da conta toda resposta
  # boa perderia pontos por não repetir a palavra da pergunta.
  #
  # Mora aqui, e não em quem usa, porque hoje são dois: o `AnswerEvaluator`,
  # que não pode dar sustentação a uma invenção por causa de um "de", e o
  # `RelevanceFloor`, que não pode achar que uma pergunta sem resposta no
  # acervo casou com um documento por causa de um "qual a". Duas listas
  # divergiriam, e a divergência apareceria como nota que não bate com recusa.
  STOPWORDS = %w[
    a ao aos as às com como da das de do dos e em entre me na nas no nos num numa o os ou para pela pelas
    pelo pelos por que se sem ser sob sobre um uma umas uns é são foi era está estão têm tem
    onde qual quais quando quanta quantas quanto quantos quem quê
  ].to_set.freeze

  def self.tokens(text)
    text.to_s.downcase.scan(PATTERN)
  end

  # Os termos que carregam conteúdo. Quem mede "isto tem a ver com aquilo"
  # precisa desta lista: palavra funcional aparece em qualquer texto em
  # português e daria casamento de graça.
  def self.meaningful(text)
    tokens(text).reject { |token| STOPWORDS.include?(token) }
  end
end
