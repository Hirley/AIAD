# frozen_string_literal: true

require_relative '../lib/react_parser'

RSpec.describe ReactParser do
  subject(:parser) { described_class.new }

  describe '#parse' do
    it 'reads an action with its input' do
      step = parser.parse(<<~TEXT)
        Pensamento: preciso consultar os documentos.
        Ação: buscar
        Entrada: {"termo": "férias"}
      TEXT

      expect(step).to include(type: :action, tool: 'buscar', input: '{"termo": "férias"}')
    end

    it 'keeps the thought, which is what makes the trace auditable' do
      step = parser.parse("Pensamento: preciso consultar.\nAção: buscar\nEntrada: férias")

      expect(step[:thought]).to eq('preciso consultar.')
    end

    it 'reads a final answer' do
      step = parser.parse("Pensamento: já sei.\nResposta Final: são 30 dias.")

      expect(step).to include(type: :answer, answer: 'são 30 dias.')
    end

    it 'reads a multi-line final answer' do
      step = parser.parse("Resposta Final: são 30 dias.\nO pedido vai ao gestor.")

      expect(step[:answer]).to eq("são 30 dias.\nO pedido vai ao gestor.")
    end

    it 'accepts the action written without accents, as models often do' do
      expect(parser.parse("Acao: buscar\nEntrada: férias")).to include(type: :action, tool: 'buscar')
    end

    it 'accepts an action with no input' do
      expect(parser.parse('Ação: relogio')).to include(type: :action, tool: 'relogio', input: nil)
    end

    # O modelo adora inventar a observação e continuar sozinho. Se aceitássemos
    # isso, ele responderia com base em resultado que nunca existiu.
    it 'stops at the first action, ignoring an observation the model invented' do
      step = parser.parse(<<~TEXT)
        Ação: buscar
        Entrada: férias
        Observação: 30 dias
        Resposta Final: são 30 dias.
      TEXT

      expect(step).to include(type: :action, tool: 'buscar', input: 'férias')
    end

    # Responder junto com a ação significa responder antes de ver o resultado.
    it 'prefers the action when the model emits both an action and an answer' do
      step = parser.parse("Ação: buscar\nEntrada: férias\nResposta Final: chutei.")

      expect(step[:type]).to eq(:action)
    end

    it 'reports text it cannot understand' do
      expect(parser.parse('bom dia, tudo bem?')).to include(type: :unknown)
    end

    it 'reports empty text' do
      expect(parser.parse('')).to include(type: :unknown)
    end

    it 'ignores an action with a blank name' do
      expect(parser.parse("Ação:   \nEntrada: férias")[:type]).to eq(:unknown)
    end
  end
end
