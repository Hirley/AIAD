# frozen_string_literal: true

require_relative '../lib/plan_parser'

RSpec.describe PlanParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'reads a numbered plan' do
      plan = parser.parse("Plano:\n1. Buscar a política de férias.\n2. Contar os dias.")

      expect(plan).to eq(['Buscar a política de férias.', 'Contar os dias.'])
    end

    it 'drops the preamble the model writes before the list' do
      plan = parser.parse("Vou resolver assim.\n\n1. Primeiro passo\n2. Segundo passo")

      expect(plan).to eq(['Primeiro passo', 'Segundo passo'])
    end

    it 'accepts a parenthesis after the number' do
      expect(parser.parse('1) Um')).to eq(['Um'])
    end

    it 'accepts the word "Passo" before the number' do
      expect(parser.parse("Passo 1: Um\nPasso 2: Dois")).to eq(%w[Um Dois])
    end

    it 'accepts bullets instead of numbers' do
      expect(parser.parse("- Um\n- Dois")).to eq(%w[Um Dois])
    end

    # Modelo cerca lista com crase por hábito de chat.
    it 'reads a plan wrapped in a code fence' do
      expect(parser.parse("```\n1. Um\n2. Dois\n```")).to eq(%w[Um Dois])
    end

    it 'ignores blank lines and extra spacing' do
      expect(parser.parse("  1.   Um  \n\n  2.   Dois  ")).to eq(%w[Um Dois])
    end

    it 'ignores a numbered line with nothing after the number' do
      expect(parser.parse("1.\n2. Dois")).to eq(['Dois'])
    end

    # Sem lista não há plano. Quem decide o que fazer com isso é o agente.
    it 'returns nothing when the model wrote prose instead of a list' do
      expect(parser.parse('Acho que é melhor buscar na política e depois contar.')).to be_empty
    end

    it 'returns nothing for empty text' do
      expect(parser.parse('')).to be_empty
      expect(parser.parse(nil)).to be_empty
    end
  end
end
