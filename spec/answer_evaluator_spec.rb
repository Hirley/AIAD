# frozen_string_literal: true

require_relative '../lib/answer_evaluator'

RSpec.describe AnswerEvaluator do
  subject(:evaluator) { described_class.new }

  let(:passages) do
    [{ text: 'A política de férias garante trinta dias por ano.', source: 'politica.txt' },
     { text: 'As férias podem ser divididas em três períodos.', source: 'ferias.txt' }]
  end

  def evaluate(answer, question: 'quantos dias de férias por ano?')
    evaluator.evaluate(question: question, answer: answer, passages: passages)
  end

  describe 'groundedness' do
    it 'gives full marks to an answer the context sustains' do
      expect(evaluate('A política garante trinta dias por ano.')[:groundedness]).to eq(1.0)
    end

    # O marcador de citação quebra como se fosse uma frase, e sozinho não tem
    # apoio em lugar nenhum. Contá-lo punia a resposta por fazer exatamente o
    # que se pede que ela faça: citar a origem.
    it 'does not punish an answer for carrying the citation marker' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:groundedness]).to eq(1.0)
    end

    it 'does not count the citation marker as a sentence' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:sentences]).to eq(1)
    end

    it 'keeps the marker out of the unsupported list' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:unsupported]).to be_empty
    end

    it 'gives zero to an answer the context says nothing about' do
      expect(evaluate('O reajuste salarial sai em dezembro.')[:groundedness]).to eq(0.0)
    end

    # Uma resposta com três frases certas e uma inventada precisa pontuar no
    # meio: é o grau que diz se a qualidade caiu, não um booleano.
    it 'scores sentence by sentence instead of all or nothing' do
      answer = 'A política garante trinta dias por ano. O reajuste salarial sai em dezembro.'

      expect(evaluate(answer)[:groundedness]).to be_within(0.001).of(0.5)
    end

    # O número sozinho não diz o que revisar.
    it 'names the sentences that do not stand up' do
      answer = 'A política garante trinta dias por ano. O reajuste salarial sai em dezembro.'

      expect(evaluate(answer)[:unsupported]).to eq(['O reajuste salarial sai em dezembro.'])
    end

    # Afirmar sem nada em que se apoiar é não-sustentado por definição. Devolver
    # 1 por vacuidade esconderia exatamente o caso que se quer pegar.
    it 'gives zero when there was no context at all' do
      report = evaluator.evaluate(question: 'quantos dias?', answer: 'Trinta dias.', passages: [])

      expect(report[:groundedness]).to eq(0.0)
    end

    it 'gives zero to an empty answer' do
      expect(evaluate('')[:groundedness]).to eq(0.0)
    end

    # Palavra funcional aparece em qualquer trecho e sustentaria qualquer coisa.
    it 'ignores stopwords when deciding what is supported' do
      expect(evaluate('De a para com por.')[:groundedness]).to eq(0.0)
    end
  end

  describe 'answer relevancy' do
    it 'gives full marks to an answer that speaks to the question' do
      expect(evaluate('São trinta dias de férias por ano.')[:answer_relevancy]).to eq(1.0)
    end

    it 'gives zero to an answer about something else entirely' do
      expect(evaluate('O escritório fica na avenida central.')[:answer_relevancy]).to eq(0.0)
    end
  end

  describe 'context relevancy' do
    it 'measures how much of what was retrieved has to do with the question' do
      report = evaluator.evaluate(question: 'quantos dias de férias por ano?',
                                  answer: 'Trinta.',
                                  passages: passages + [{ text: 'O café acaba às dez.', source: 'copa.txt' }])

      expect(report[:context_relevancy]).to be_within(0.001).of(2.0 / 3)
    end

    it 'is zero when nothing was retrieved' do
      report = evaluator.evaluate(question: 'quantos dias?', answer: 'Trinta.', passages: [])

      expect(report[:context_relevancy]).to eq(0.0)
    end
  end

  # Mesmo padrão do Reranker: a heurística é o padrão barato, e um juiz de
  # verdade (LLM-as-judge, cross-encoder) entra por injeção sem mexer em quem
  # chama.
  describe 'with an injected judge' do
    subject(:evaluator) { described_class.new(judge: ->(_claim, _context) { 1.0 }) }

    it 'uses the judge to decide whether a sentence stands up' do
      expect(evaluate('Qualquer invenção sobre qualquer assunto.')[:groundedness]).to eq(1.0)
    end

    it 'hands the judge the sentence and the context' do
      seen = []
      evaluator = described_class.new(judge: ->(claim, context) { seen << [claim, context] and 1.0 })
      evaluator.evaluate(question: '?', answer: 'Trinta dias.', passages: passages)

      expect(seen.first.first).to eq('Trinta dias.')
      expect(seen.first.last).to include('trinta dias por ano')
    end
  end

  it 'reports how many sentences it looked at' do
    expect(evaluate('Uma frase. Outra frase.')[:sentences]).to eq(2)
  end
end
