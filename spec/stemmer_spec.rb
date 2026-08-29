# frozen_string_literal: true

require_relative '../lib/stemmer'

RSpec.describe Stemmer do
  def stem(word) = described_class.stem(word)

  # O caso que motivou tudo: a pergunta dizia "trabalhar", o documento dizia
  # "trabalho", e a API recusava uma pergunta que o acervo respondia.
  describe 'o caso que motivou a classe' do
    it 'brings the infinitive and the noun to the same stem' do
      expect(stem('trabalhar')).to eq(stem('trabalho'))
    end

    it 'brings the conjugated form along too' do
      expect(stem('trabalhamos')).to eq(stem('trabalho'))
    end
  end

  describe 'plural' do
    it 'drops the plain s' do
      expect(stem('dias')).to eq(stem('dia'))
    end

    it 'turns -ões back into -ão' do
      expect(stem('ações')).to eq(stem('ação'))
    end

    it 'turns -ais back into -al' do
      expect(stem('mensais')).to eq(stem('mensal'))
    end

    it 'turns -ns back into -m' do
      expect(stem('bons')).to eq(stem('bom'))
    end

    # "mais" não é plural de "mal": a regra -is → -il só vale para palavra
    # longa o bastante para não ser uma dessas.
    it 'does not invent a singular for a short word ending in -is' do
      expect(stem('mais')).not_to eq(stem('mal'))
    end

    it 'still applies -is → -il to a word long enough' do
      expect(stem('barris')).to eq(stem('barril'))
    end
  end

  describe 'verbo' do
    it 'strips the infinitive ending' do
      expect(stem('reembolsar')).to eq(stem('reembolso'))
    end

    it 'strips the gerund' do
      expect(stem('trabalhando')).to eq(stem('trabalho'))
    end

    it 'strips the participle' do
      expect(stem('divididas')).to eq(stem('dividir'))
    end
  end

  describe 'advérbio' do
    it 'strips -mente' do
      expect(stem('legalmente')).to eq(stem('legal'))
    end
  end

  # Sem piso de tamanho, o stemmer come palavra curta inteira e passa a casar
  # coisas que não têm relação nenhuma.
  describe 'palavra curta' do
    it 'leaves a three-letter word alone' do
      expect(stem('ano')).to eq('ano')
    end

    it 'does not reduce a word to nothing' do
      expect(stem('as')).not_to be_empty
    end

    it 'keeps a short word that ends like a verb' do
      expect(stem('ar')).to eq('ar')
    end
  end

  describe 'o que não deve mudar' do
    # Foi o que fez `-em` sair da lista de verbo: substantivo terminado em -em
    # é comum, e a regra virava "viagem" em "viag".
    it 'leaves a noun that ends like a verb conjugation alone' do
      expect(stem('viagem')).to eq('viagem')
    end

    it 'leaves the other -em nouns alone too' do
      expect([stem('ordem'), stem('imagem'), stem('homem')]).to eq(%w[ordem imagem homem])
    end

    it 'is idempotent, so stemming twice is the same as once' do
      expect(stem(stem('trabalhando'))).to eq(stem('trabalhando'))
    end

    it 'handles an empty string' do
      expect(stem('')).to eq('')
    end
  end

  # Stemming conflaciona: é o preço, não um defeito. O que não pode é
  # conflacionar palavras de assuntos diferentes no corpus que importa.
  describe 'não conflaciona o que o acervo precisa distinguir' do
    it 'keeps férias apart from feriado' do
      expect(stem('férias')).not_to eq(stem('feriado'))
    end

    it 'keeps reembolso apart from bolso' do
      expect(stem('reembolso')).not_to eq(stem('bolso'))
    end
  end

  describe '.stems' do
    it 'stems every token of a text' do
      expect(described_class.stems('trabalhar remotamente')).to eq(%w[trabalh remot])
    end

    it 'gives back nothing for an empty text' do
      expect(described_class.stems('')).to be_empty
    end
  end
end
