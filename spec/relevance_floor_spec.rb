# frozen_string_literal: true

require_relative '../lib/relevance_floor'

RSpec.describe RelevanceFloor do
  subject(:floor) { described_class.new }

  def passage(text, source: 'doc.txt')
    { text: text, source: source, score: 0.03 }
  end

  let(:ferias) { passage('A política de férias garante trinta dias corridos por ano.') }
  let(:reembolso) { passage('O reembolso de viagem cobre passagem, hospedagem e alimentação.') }

  describe 'keeping what has to do with the question' do
    it 'keeps the passage that answers it' do
      expect(floor.apply('quantos dias de férias', [ferias])).to eq([ferias])
    end

    it 'drops the passage that has nothing to do with it' do
      expect(floor.apply('qual a política de plano odontológico', [reembolso])).to be_empty
    end

    it 'keeps only the ones that pass, out of several' do
      expect(floor.apply('quantos dias de férias', [ferias, reembolso])).to eq([ferias])
    end

    it 'keeps the order it was given' do
      kept = floor.apply('quantos dias de férias e reembolso de viagem', [reembolso, ferias])

      expect(kept.map { |p| p[:text] }).to eq([reembolso[:text], ferias[:text]])
    end
  end

  # O caso que motiva a classe: recuperador sempre devolve o top-k, por pior
  # que seja o melhor. Devolver tudo vazio é o que faz o pipeline responder
  # "não encontrei" em vez de citar um documento qualquer com convicção.
  describe 'when nothing is good enough' do
    it 'gives back nothing' do
      expect(floor.apply('qual o prazo do aviso prévio', [ferias, reembolso])).to be_empty
    end
  end

  # Palavra funcional aparece em qualquer texto em português. Sem tirá-las da
  # conta, "qual a política de" já casava com qualquer documento e o piso não
  # separava pergunta respondível de pergunta sem resposta no acervo.
  describe 'the function words do not count' do
    it 'does not let "qual a política de" carry a passage on its own' do
      expect(floor.apply('qual a política de previdência privada', [ferias])).to be_empty
    end

    # Sem termo de conteúdo não há nada para casar, e aprovar por vacuidade
    # seria pior do que recusar: passaria tudo.
    it 'drops everything for a question made only of function words' do
      expect(floor.apply('o que é que é', [ferias])).to be_empty
    end
  end

  # O padrão foi calibrado em onze perguntas e três documentos, o que não
  # calibra uma constante. Ele precisa ser ajustável sem tocar em código.
  describe 'o valor do piso' do
    # Meio termo casado (dias e férias, de quatro termos) passa no padrão e cai
    # num piso exigente.
    it 'is configurable' do
      pergunta = 'quantos dias de férias e reembolso de viagem'

      expect(floor.apply(pergunta, [ferias])).to eq([ferias])
      expect(described_class.new(minimum: 0.6).apply(pergunta, [ferias])).to be_empty
    end

    it 'lets everything through when set to zero' do
      expect(described_class.new(minimum: 0.0).apply('aviso prévio', [ferias])).to eq([ferias])
    end

    # Mesmo desenho do Reranker e do AnswerEvaluator: heurística barata por
    # padrão, juiz de verdade por injeção.
    it 'takes an injected scorer' do
      generous = described_class.new(scorer: ->(_question, _text) { 1.0 })

      expect(generous.apply('qualquer coisa', [ferias])).to eq([ferias])
    end
  end

  describe 'nothing to do' do
    it 'handles an empty list' do
      expect(floor.apply('quantos dias de férias', [])).to be_empty
    end

    it 'does not blow up on a passage without text' do
      expect(floor.apply('quantos dias de férias', [{ source: 'vazio.txt' }])).to be_empty
    end
  end
end
