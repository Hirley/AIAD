# frozen_string_literal: true

require_relative '../lib/prompt_builder'

RSpec.describe PromptBuilder do
  subject(:builder) { described_class.new }

  let(:passages) do
    [
      { text: 'A política de férias garante trinta dias por ano.', source: 'politica.txt' },
      { text: 'As férias podem ser divididas em até três períodos.', source: 'politica.txt' }
    ]
  end

  describe '#build' do
    it 'includes the default instruction' do
      expect(builder.build('Quantos dias de férias?', passages)).to include(described_class::DEFAULT_INSTRUCTION)
    end

    it 'accepts a custom instruction' do
      custom = described_class.new(instruction: 'Responda em uma frase.')

      expect(custom.build('Quantos dias?', passages)).to include('Responda em uma frase.')
    end

    it 'numbers each passage and cites its source' do
      prompt = builder.build('Quantos dias de férias?', passages)

      expect(prompt).to include('[1] (origem: politica.txt)')
      expect(prompt).to include('[2] (origem: politica.txt)')
    end

    it 'includes the text of every passage' do
      prompt = builder.build('Quantos dias de férias?', passages)

      expect(prompt).to include('trinta dias por ano').and include('três períodos')
    end

    it 'includes the question' do
      expect(builder.build('Quantos dias de férias?', passages)).to include('Quantos dias de férias?')
    end

    it 'marks the passage as unknown when it has no source' do
      expect(builder.build('Pergunta', [{ text: 'trecho' }])).to include('[1] (origem: desconhecida)')
    end

    it 'raises when there is no passage to ground the answer' do
      expect { builder.build('Pergunta', []) }.to raise_error(PromptBuilder::EmptyContextError)
    end
  end
end
