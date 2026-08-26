# frozen_string_literal: true

require_relative '../lib/extractive_llm'
require_relative '../lib/prompt_builder'

RSpec.describe ExtractiveLlm do
  subject(:llm) { described_class.new }

  let(:prompt) do
    PromptBuilder.new.build(
      'Quantos dias de férias?',
      [{ text: 'A política garante trinta dias por ano.', source: 'politica.txt' },
       { text: 'Divisíveis em três períodos.', source: 'ferias.txt' }]
    )
  end

  describe '#complete' do
    it 'returns the most relevant excerpt, citing it' do
      expect(llm.complete(prompt)).to eq('A política garante trinta dias por ano. [1]')
    end

    it 'never invents content: the answer is contained in the prompt' do
      answer = llm.complete(prompt).sub(' [1]', '')

      expect(prompt).to include(answer)
    end

    it 'says it does not know when the prompt has no context' do
      expect(llm.complete('Pergunta solta, sem contexto nenhum')).to eq(described_class::NO_ANSWER)
    end
  end
end
