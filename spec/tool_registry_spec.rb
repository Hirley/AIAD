# frozen_string_literal: true

require_relative '../lib/tool_registry'

RSpec.describe ToolRegistry do
  let(:search) do
    Tool.new(name: 'buscar', description: 'Busca nos documentos.', parameters: { termo: 'o texto' }) do |arguments|
      "resultado para #{arguments[:termo]}"
    end
  end

  let(:clock) { Tool.new(name: 'relogio', description: 'Informa a hora.') { 'meio-dia' } }

  subject(:registry) { described_class.new([search, clock]) }

  describe '#invoke' do
    it 'runs the requested tool' do
      expect(registry.invoke('buscar', termo: 'férias')).to eq('resultado para férias')
    end

    it 'converts the result to text, since the agent reads it as an observation' do
      counter = described_class.new([Tool.new(name: 'contar', description: 'Conta.') { 42 }])

      expect(counter.invoke('contar')).to eq('42')
    end

    # As três situações abaixo devolvem observação em vez de estourar: o agente
    # precisa poder ler o erro e tentar de novo, e não morrer no meio do laço.
    it 'reports an unknown tool listing what is available' do
      observation = registry.invoke('inventada')

      expect(observation).to include('inventada').and include('buscar').and include('relogio')
    end

    it 'reports invalid arguments instead of raising' do
      expect(registry.invoke('buscar')).to include('faltam argumentos').and include('termo')
    end

    it 'reports a failure inside the tool instead of raising' do
      broken = described_class.new([Tool.new(name: 'quebrada', description: 'Falha.') { raise 'sem conexão' }])

      expect(broken.invoke('quebrada')).to include('sem conexão')
    end

    it 'does not let a tool failure look like a successful answer' do
      broken = described_class.new([Tool.new(name: 'quebrada', description: 'Falha.') { raise 'sem conexão' }])

      expect(broken.invoke('quebrada')).to start_with('Erro')
    end
  end

  describe '#catalog' do
    it 'lists every tool signature for the prompt' do
      expect(registry.catalog).to eq(
        "- buscar(termo: o texto) — Busca nos documentos.\n- relogio — Informa a hora."
      )
    end

    it 'says plainly when there is no tool available' do
      expect(described_class.new([]).catalog).to include('Nenhuma ferramenta')
    end
  end

  describe '#names' do
    it 'exposes the registered names' do
      expect(registry.names).to eq(%w[buscar relogio])
    end
  end

  describe 'registration' do
    it 'refuses two tools with the same name, which would make the choice ambiguous' do
      expect { described_class.new([search, search]) }.to raise_error(ArgumentError, /buscar/)
    end
  end
end
