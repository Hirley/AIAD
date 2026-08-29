# frozen_string_literal: true

require_relative '../lib/tokenizer'

RSpec.describe Tokenizer do
  describe '.tokens' do
    it 'breaks the text into lowercase terms' do
      expect(described_class.tokens('Trinta Dias por ano')).to eq(%w[trinta dias por ano])
    end

    it 'drops punctuation' do
      expect(described_class.tokens('férias, trinta dias.')).to eq(%w[férias trinta dias])
    end
  end

  # A lista mora aqui porque duas coisas dependem dela e precisam concordar: o
  # avaliador, que não pode dar sustentação a uma invenção por causa de um
  # "de", e o piso de relevância, que não pode achar que uma pergunta sem
  # resposta no acervo casou com um documento por causa de um "qual a".
  describe '.meaningful' do
    it 'drops the function words' do
      expect(described_class.meaningful('qual a política de férias')).to eq(%w[política férias])
    end

    # "quantos", "quando" e "qual" nunca aparecem na resposta: sem tirá-las da
    # conta, toda resposta boa perderia pontos por não repetir a pergunta.
    it 'drops the question words too' do
      expect(described_class.meaningful('quantos dias')).to eq(['dias'])
    end

    it 'keeps the order and the repetitions the caller may want to count' do
      expect(described_class.meaningful('férias e férias')).to eq(%w[férias férias])
    end

    # Pergunta feita só de palavras funcionais não tem termo nenhum para casar,
    # e quem chama precisa poder distinguir isso de "não casou nada".
    it 'gives back nothing when there is nothing but function words' do
      expect(described_class.meaningful('o que é que é')).to be_empty
    end
  end
end
