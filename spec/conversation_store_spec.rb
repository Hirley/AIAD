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
end
