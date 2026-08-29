# frozen_string_literal: true

require_relative '../lib/conversation_store'

RSpec.describe ConversationStore do
  subject(:store) { described_class.new }

  it_behaves_like 'a conversation store'

  # Devolver a lista interna deixaria quem chamou alterar a conversa guardada
  # sem passar por `save` — e o store em disco nunca se comportaria assim.
  it 'does not let the caller change what is stored by mutating what it read' do
    store.save('sessao', [{ role: 'user', content: 'oi' }])
    store.load('sessao') << { role: 'user', content: 'intruso' }

    expect(store.load('sessao').size).to eq(1)
  end

  # Uma rota que cria uma sessão nova a cada pergunta sem `session` encheria o
  # Hash até o processo morrer — e o vazamento só apareceria semanas depois,
  # em produção, sem nada apontando para cá.
  describe 'teto de conversas' do
    subject(:store) { described_class.new(max_sessions: 3) }

    def save(id)
      store.save(id, [{ role: 'user', content: "pergunta #{id}" }])
    end

    it 'keeps the number of conversations under the ceiling' do
      10.times { |i| save("sessao-#{i}") }

      expect(store.size).to eq(3)
    end

    it 'drops the oldest conversation first' do
      save('primeira')
      save('segunda')
      save('terceira')
      save('quarta')

      expect(store.load('primeira')).to be_empty
    end

    it 'keeps the newest ones' do
      4.times { |i| save("sessao-#{i}") }

      expect(store.load('sessao-3')).not_to be_empty
    end

    # Conversa consultada agora não pode ser descartada como se estivesse
    # parada: é justamente a que alguém está usando.
    it 'treats a read as use, so an active conversation is not evicted' do
      save('antiga')
      save('outra')
      save('mais-uma')
      store.load('antiga')
      save('nova')

      expect(store.load('antiga')).not_to be_empty
    end

    it 'evicts the one that was really idle' do
      save('antiga')
      save('outra')
      save('mais-uma')
      store.load('antiga')
      save('nova')

      expect(store.load('outra')).to be_empty
    end

    it 'writing to a conversation also counts as use' do
      save('primeira')
      save('segunda')
      save('terceira')
      save('primeira')
      save('quarta')

      expect(store.load('primeira')).not_to be_empty
    end
  end
end
