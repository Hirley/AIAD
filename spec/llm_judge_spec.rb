# frozen_string_literal: true

require_relative '../lib/llm_judge'

RSpec.describe LlmJudge do
  let(:contexto) do
    'A política de férias da empresa garante trinta dias corridos por ano a todo empregado com mais de ' \
      'doze meses de casa.'
  end

  # O par exato da tabela da issue #19: as duas frases tiram a mesma nota
  # léxica (nenhuma reaproveita o vocabulário do trecho), e uma delas está
  # certa.
  let(:parafrase) { 'O colaborador tem direito a um mês inteiro de descanso remunerado a cada período aquisitivo.' }
  let(:alucinacao) { 'O reajuste salarial sai em dezembro para todos os cargos.' }

  describe '#call' do
    it 'scores a correct paraphrase above a plausible fabrication' do
      parafrase_score = described_class.new(llm: ScriptedLlm.new('sim')).call(parafrase, contexto)
      alucinacao_score = described_class.new(llm: ScriptedLlm.new('não')).call(alucinacao, contexto)

      expect(parafrase_score).to be > alucinacao_score
    end

    it 'gives full marks when the model says the claim is supported' do
      expect(described_class.new(llm: ScriptedLlm.new('sim')).call(parafrase, contexto)).to eq(1.0)
    end

    it 'gives no marks when the model says the claim is not supported' do
      expect(described_class.new(llm: ScriptedLlm.new('não')).call(alucinacao, contexto)).to eq(0.0)
    end

    # A resposta do modelo não vem em formato fixo, e "não sustentado" é o
    # lado seguro de um texto que a análise não reconhece.
    it 'treats an unparseable answer as unsupported' do
      expect(described_class.new(llm: ScriptedLlm.new('talvez, depende')).call(parafrase, contexto)).to eq(0.0)
    end

    it 'sends the claim and the context to the model' do
      llm = ScriptedLlm.new('sim')
      described_class.new(llm: llm).call(parafrase, contexto)

      expect(llm.prompts.last).to include(parafrase)
      expect(llm.prompts.last).to include(contexto)
    end
  end
end
