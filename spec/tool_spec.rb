# frozen_string_literal: true

require_relative '../lib/tool'

RSpec.describe Tool do
  subject(:tool) do
    described_class.new(
      name: 'buscar',
      description: 'Busca um termo nos documentos indexados.',
      parameters: { termo: 'o texto a procurar' }
    ) { |arguments| "encontrei #{arguments[:termo]}" }
  end

  describe '#call' do
    it 'runs the handler with the given arguments' do
      expect(tool.call(termo: 'férias')).to eq('encontrei férias')
    end

    it 'accepts arguments with string keys, as they arrive from the model' do
      expect(tool.call('termo' => 'férias')).to eq('encontrei férias')
    end

    it 'rejects a call missing a required argument' do
      expect { tool.call({}) }.to raise_error(Tool::InvalidArgumentsError, /termo/)
    end

    it 'rejects an argument the tool does not declare' do
      expect { tool.call(termo: 'férias', pagina: 2) }.to raise_error(Tool::InvalidArgumentsError, /pagina/)
    end
  end

  describe 'declaration' do
    it 'requires a name' do
      expect { described_class.new(name: ' ', description: 'x') { 'ok' } }.to raise_error(ArgumentError)
    end

    it 'requires a description, since it is what tells the model when to use the tool' do
      expect { described_class.new(name: 'buscar', description: '') { 'ok' } }.to raise_error(ArgumentError)
    end

    it 'requires a handler' do
      expect { described_class.new(name: 'buscar', description: 'x') }.to raise_error(ArgumentError)
    end

    it 'accepts a callable handler instead of a block' do
      callable = described_class.new(name: 'oi', description: 'Cumprimenta.', handler: ->(_args) { 'olá' })

      expect(callable.call({})).to eq('olá')
    end
  end

  describe '#signature' do
    it 'describes the tool and its parameters for the prompt' do
      expect(tool.signature).to eq('buscar(termo: o texto a procurar) — Busca um termo nos documentos indexados.')
    end

    it 'omits the parentheses when the tool takes no arguments' do
      clock = described_class.new(name: 'relogio', description: 'Informa a hora.') { 'meio-dia' }

      expect(clock.signature).to eq('relogio — Informa a hora.')
    end
  end
end
