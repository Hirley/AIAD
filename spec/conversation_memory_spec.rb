# frozen_string_literal: true

require_relative '../lib/conversation_memory'

RSpec.describe ConversationMemory do
  subject(:memory) { described_class.new }

  def converse(id = 'sessao')
    memory.append(id, role: :user, content: 'quantos dias de férias?')
    memory.append(id, role: :assistant, content: 'trinta por ano.')
  end

  describe 'keeping the turns' do
    it 'reads back what was said' do
      converse

      expect(memory.turns('sessao')).to eq([{ role: :user, content: 'quantos dias de férias?' },
                                            { role: :assistant, content: 'trinta por ano.' }])
    end

    it 'starts empty' do
      expect(memory.turns('nova')).to be_empty
    end

    it 'keeps conversations apart' do
      converse('uma')

      expect(memory.turns('outra')).to be_empty
    end

    it 'clears a conversation' do
      converse
      memory.clear('sessao')

      expect(memory.turns('sessao')).to be_empty
    end

    # Papel errado passaria em silêncio e sairia como rótulo torto no prompt.
    it 'refuses a role it does not know' do
      expect { memory.append('sessao', role: :sistema, content: 'oi') }
        .to raise_error(ArgumentError, /sistema/)
    end
  end

  # O motivo de o store ser injetado: a conversa continua depois do processo.
  describe 'persistence' do
    it 'reads a conversation another memory left in the same store' do
      store = ConversationStore.new
      described_class.new(store: store).append('sessao', role: :user, content: 'oi')

      expect(described_class.new(store: store).turns('sessao').first[:content]).to eq('oi')
    end

    # O store guarda texto puro, porque atravessa JSON. Quem sabe que papel é
    # símbolo é esta classe.
    it 'gives the role back as a symbol even coming from a store that only knows text' do
      store = ConversationStore.new
      store.save('sessao', [{ role: 'assistant', content: 'olá' }])

      expect(described_class.new(store: store).turns('sessao').first[:role]).to eq(:assistant)
    end
  end

  # Conversa cresce sem parar e o histórico inteiro é pago em toda chamada.
  describe 'the token budget' do
    subject(:memory) { described_class.new(budget: budget) }

    context 'when everything fits' do
      let(:budget) { 1000 }

      it 'keeps every turn' do
        converse

        expect(memory.history('sessao').size).to eq(2)
      end
    end

    context 'when the budget is tight' do
      let(:budget) { 5 }

      it 'drops the oldest turns first' do
        converse

        expect(memory.history('sessao')).to eq([{ role: :assistant, content: 'trinta por ano.' }])
      end

      it 'leaves what was actually said untouched in the store' do
        converse

        expect(memory.turns('sessao').size).to eq(2)
      end
    end

    # Cortar a fala mais recente é pior do que estourar o orçamento: sem ela o
    # histórico não serve para nada.
    context 'when a single turn busts the budget by itself' do
      let(:budget) { 1 }

      it 'keeps the most recent turn anyway' do
        converse

        expect(memory.history('sessao').size).to eq(1)
      end
    end
  end

  describe 'the transcript' do
    it 'labels who said what' do
      converse

      expect(memory.transcript('sessao')).to eq("Usuário: quantos dias de férias?\nAssistente: trinta por ano.")
    end

    it 'is empty for a conversation that has not started' do
      expect(memory.transcript('nova')).to be_empty
    end

    it 'renders only what fits the budget' do
      memory = described_class.new(budget: 5)
      memory.append('sessao', role: :user, content: 'quantos dias de férias?')
      memory.append('sessao', role: :assistant, content: 'trinta por ano.')

      expect(memory.transcript('sessao')).to eq('Assistente: trinta por ano.')
    end
  end

  # Duas contas diferentes: o orçamento é sobre custo por chamada e é apertado;
  # a retenção é sobre memória do processo e é folgada. Sem teto, uma conversa
  # longa cresce para sempre — e o prompt continuaria certo o tempo todo, o que
  # faz o problema não aparecer até o processo morrer.
  describe 'retenção' do
    subject(:memory) { described_class.new(retention: 3) }

    def falar(numero)
      memory.append('sessao', role: :user, content: "pergunta #{numero}")
    end

    it 'keeps only the configured number of turns' do
      5.times { |i| falar(i) }

      expect(memory.turns('sessao').size).to eq(3)
    end

    it 'keeps the most recent ones, because a conversation is read from the end' do
      5.times { |i| falar(i) }

      expect(memory.turns('sessao').map { |turn| turn[:content] })
        .to eq(['pergunta 2', 'pergunta 3', 'pergunta 4'])
    end

    it 'does not touch a conversation that is under the ceiling' do
      2.times { |i| falar(i) }

      expect(memory.turns('sessao').size).to eq(2)
    end

    # A retenção não pode apertar o histórico mais do que o orçamento já
    # aperta: quem manda no prompt continua sendo o orçamento.
    it 'leaves the budget in charge of what reaches the prompt' do
      memory = described_class.new(retention: 10, budget: 5)
      memory.append('sessao', role: :user, content: 'quantos dias de férias?')
      memory.append('sessao', role: :assistant, content: 'trinta por ano.')

      expect(memory.transcript('sessao')).to eq('Assistente: trinta por ano.')
    end
  end
end
