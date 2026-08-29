# frozen_string_literal: true

require_relative 'tokenizer'

# Redução de palavra ao radical, em português.
#
# Existe por causa de um defeito concreto: a pergunta dizia "trabalh**ar**", o
# documento dizia "trabalh**o**", e o piso de relevância recusava uma pergunta
# que o acervo respondia. Para quem casa termo com termo, morfologia é ruído —
# "dias" e "dia", "divididas" e "dividir" são a mesma ideia.
#
# **É um subconjunto reduzido do RSLP, e não o RSLP inteiro.** O algoritmo
# original tem oito passos e algumas centenas de regras, com listas de exceção
# que só se acertam consultando a publicação. Escrever isso de memória seria
# escrever errado com aparência de certo — e stemmer errado não falha, ele
# conflaciona em silêncio e estraga o ranking. O que está aqui cobre plural,
# advérbio, as formas verbais comuns e a vogal final, que é o que o corpus
# deste projeto exercita. Quando não for suficiente, o caminho é trocar por uma
# implementação completa, e o desenho já permite: quem chama depende de
# `stem` e de mais nada.
#
# Quatro decisões definem o comportamento:
#
# - **Não entra no caminho dos embeddings.** O `EmbeddingGenerator` projeta
#   cada termo por hash; stemizar ali mudaria todo vetor já gravado no Qdrant e
#   exigiria reingestão do acervo. E há um motivo mais forte: o embedder de
#   hash é substituto de um modelo de verdade, e modelo de verdade trata
#   morfologia sozinho — receber texto pré-stemizado o deixaria pior.
# - **Piso de tamanho em toda regra.** Sem ele o stemmer come palavra curta
#   inteira e passa a casar coisas sem relação: "ar" viraria "" e casaria com
#   tudo. Cada regra declara o tamanho mínimo que o radical precisa ter para
#   ela valer.
# - **Um passo por vez, primeira regra que casar.** Aplicar várias regras do
#   mesmo passo empilharia cortes e comeria a palavra.
# - **Conflacionar é o preço, não o defeito.** "casa" e "casar" viram o mesmo
#   radical, e é assim que stemmer funciona. O que se controla é conflacionar
#   demais, e é para isso que serve o piso de tamanho.
module Stemmer
  # Cada regra é [sufixo, tamanho mínimo do radical, substituição].
  # Ordenadas da mais longa para a mais curta: "trabalhamos" tem de casar com
  # "amos" antes de casar com "os".
  #
  # Sem `-am` e `-em`, de propósito. São terminações de terceira pessoa do
  # plural, mas também o fim de muito substantivo comum — "viagem", "ordem",
  # "imagem", "homem". Aplicá-las trocava "viagem" por "viag" e casava um
  # substantivo com qualquer verbo de mesmo radical. O RSLP resolve isso com
  # lista de exceção; sem a lista, o certo é abrir mão da regra. O preço é
  # "podem" não casar com "pode".
  VERB = [
    ['aríamos', 3, ''], ['eríamos', 3, ''], ['iríamos', 3, ''],
    ['ássemos', 3, ''], ['êssemos', 3, ''], ['íssemos', 3, ''],
    ['aremos', 3, ''], ['eremos', 3, ''], ['iremos', 3, ''],
    ['áramos', 3, ''], ['éramos', 3, ''], ['íramos', 3, ''],
    ['ávamos', 3, ''], ['aríeis', 3, ''], ['eríeis', 3, ''], ['iríeis', 3, ''],
    ['aríamo', 3, ''], ['eríamo', 3, ''], ['iríamo', 3, ''],
    ['ássemo', 3, ''], ['êssemo', 3, ''], ['íssemo', 3, ''],
    ['aremo', 3, ''], ['eremo', 3, ''], ['iremo', 3, ''],
    ['áramo', 3, ''], ['éramo', 3, ''], ['íramo', 3, ''], ['ávamo', 3, ''],
    ['amos', 3, ''], ['emos', 3, ''], ['imos', 3, ''],
    ['amo', 3, ''], ['emo', 3, ''], ['imo', 3, ''],
    ['aram', 3, ''], ['eram', 3, ''], ['iram', 3, ''], ['avam', 3, ''],
    ['arão', 3, ''], ['erão', 3, ''], ['irão', 3, ''],
    ['asse', 3, ''], ['esse', 3, ''], ['isse', 3, ''],
    ['ando', 3, ''], ['endo', 3, ''], ['indo', 3, ''],
    ['aria', 3, ''], ['eria', 3, ''], ['iria', 3, ''],
    ['ada', 3, ''], ['ado', 3, ''], ['ida', 3, ''], ['ido', 3, ''],
    ['ava', 3, ''], ['iam', 3, ''],
    ['ei', 3, ''], ['eu', 3, ''], ['iu', 3, ''], ['ou', 3, ''],
    ['ar', 3, ''], ['er', 3, ''], ['ir', 3, '']
  ].freeze

  PLURAL = [
    ['ões', 2, 'ão'], ['ães', 2, 'ão'], ['ais', 3, 'al'], ['éis', 3, 'el'],
    ['eis', 3, 'el'], ['óis', 3, 'ol'], ['is', 4, 'il'], ['ns', 2, 'm'],
    ['res', 3, 'r'], ['les', 3, 'l'], ['s', 2, '']
  ].freeze

  ADVERB = [['mente', 4, '']].freeze

  VOWEL = [['a', 3, ''], ['e', 3, ''], ['o', 3, '']].freeze

  # A ordem dos passos importa, e a errada custou duas tentativas.
  #
  # **Plural primeiro**, agindo sobre a palavra como ela chegou. A tentação é
  # pôr verbo na frente, porque "trabalhamos" é forma verbal e não plural de
  # nada — mas com verbo primeiro o passo de plural depois arranca o `-s` de um
  # radical que não é plural: "reembolsar" virava "reembols" e então
  # "reembol". Por isso a lista de verbo traz as formas **sem o `-s`**
  # (`-amo`, `-aremo`): quando o verbo é conjugado no plural, o passo anterior
  # já tirou o `s`, e é essa forma que chega aqui.
  #
  # **Vogal por último**, porque é o corte mais grosseiro e só deve agir sobre
  # o que os passos com critério já não quiseram.
  STEPS = [PLURAL, ADVERB, VERB, VOWEL].freeze

  def self.stem(word)
    STEPS.reduce(word.to_s.downcase) { |current, step| apply(current, step) }
  end

  def self.stems(text)
    Tokenizer.tokens(text).map { |token| stem(token) }
  end

  # Radicais só dos termos que carregam conteúdo. Existe aqui, e não no
  # `Tokenizer`, para a dependência ficar num sentido só: o stemmer conhece a
  # tokenização, a tokenização não conhece o stemmer.
  def self.meaningful_stems(text)
    Tokenizer.meaningful(text).map { |token| stem(token) }
  end

  # Primeira regra que casar vence, e só ela. Se o radical resultante ficar
  # menor que o mínimo declarado, a regra não vale e a palavra segue inteira
  # para o passo seguinte.
  def self.apply(word, step)
    step.each do |suffix, minimum, replacement|
      next unless word.end_with?(suffix)

      root = word[0...-suffix.length]
      return root + replacement if root.length >= minimum
    end

    word
  end
  private_class_method :apply
end
