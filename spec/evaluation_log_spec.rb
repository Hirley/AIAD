# frozen_string_literal: true

require_relative '../lib/evaluation_log'

RSpec.describe EvaluationLog do
  subject(:log) { described_class.new }

  def record(groundedness: 1.0, answer_relevancy: 1.0, context_relevancy: 1.0, question: 'q', answer: 'a')
    log.record(question: question, answer: answer,
               scores: { groundedness: groundedness, answer_relevancy: answer_relevancy,
                         context_relevancy: context_relevancy })
  end

  describe 'averages' do
    it 'counts how many answers it saw' do
      2.times { record }

      expect(log.averages[:samples]).to eq(2)
    end

    it 'averages each score on its own' do
      record(groundedness: 1.0, answer_relevancy: 0.5)
      record(groundedness: 0.0, answer_relevancy: 0.5)

      expect(log.averages).to include(groundedness: 0.5, answer_relevancy: 0.5)
    end

    it 'is all zero before anything was recorded' do
      expect(log.averages).to include(samples: 0, groundedness: 0.0)
    end
  end

  describe 'the worst answers' do
    # A média diz que piorou; a lista diz o que ler.
    it 'keeps the least grounded ones first' do
      record(groundedness: 1.0, question: 'boa')
      record(groundedness: 0.2, question: 'ruim')
      record(groundedness: 0.6, question: 'media')

      expect(log.worst.map { |entry| entry[:question] }).to eq(%w[ruim media boa])
    end

    it 'keeps the question and the answer, not just the number' do
      record(groundedness: 0.2, question: 'quantos dias?', answer: 'Noventa.')

      expect(log.worst.first).to include(question: 'quantos dias?', answer: 'Noventa.')
    end

    it 'takes as many as asked for' do
      3.times { |index| record(groundedness: index / 10.0) }

      expect(log.worst(2).size).to eq(2)
    end

    # Um log que guarda tudo vaza memória num serviço que roda semanas. A média
    # é corrente e não cresce; a lista das piores é limitada de propósito.
    it 'never grows past the limit it was given' do
      log = described_class.new(keep: 2)
      5.times { |index| log.record(question: "q#{index}", answer: 'a', scores: { groundedness: index / 10.0 }) }

      expect(log.worst(10).size).to eq(2)
    end

    it 'keeps the worst ones when it has to drop some' do
      log = described_class.new(keep: 2)
      [0.9, 0.1, 0.5].each { |score| log.record(question: score.to_s, answer: 'a', scores: { groundedness: score }) }

      expect(log.worst.map { |entry| entry[:question] }).to eq(%w[0.1 0.5])
    end

    it 'still counts the ones it dropped in the average' do
      log = described_class.new(keep: 1)
      [1.0, 0.0].each { |score| log.record(question: 'q', answer: 'a', scores: { groundedness: score }) }

      expect(log.averages).to include(samples: 2, groundedness: 0.5)
    end
  end
end
