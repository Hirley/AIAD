# frozen_string_literal: true

# Contrato que todo store de conversa precisa cumprir, exercitado igual pelo
# store em memória e pelo store em disco. É o que garante que trocar um pelo
# outro não muda o comportamento do que está em cima.
#
# Os valores dos turnos são texto puro de propósito: o store guarda hash que
# atravessa JSON, e não sabe o que é um papel de conversa. Quem converte papel
# em símbolo é a `ConversationMemory`, que é quem tem esse conceito. Se o store
# normalizasse valores, o de memória e o de disco divergiriam na primeira coisa
# que não fosse texto.
RSpec.shared_examples 'a conversation store' do
  let(:turns) { [{ role: 'user', content: 'oi' }, { role: 'assistant', content: 'olá' }] }

  it 'starts empty for a conversation that never happened' do
    expect(store.load('nova')).to be_empty
  end

  it 'reads back what it saved' do
    store.save('sessao', turns)

    expect(store.load('sessao')).to eq(turns)
  end

  # JSON não tem símbolo. Sem normalizar as chaves na volta, o store em disco
  # devolveria chave de texto e quem está em cima quebraria só depois de
  # reiniciar — o pior momento para descobrir.
  it 'gives the keys back as symbols' do
    store.save('sessao', turns)

    expect(store.load('sessao').first.keys).to eq(%i[role content])
  end

  it 'keeps the turns in the order they happened' do
    store.save('sessao', turns)

    expect(store.load('sessao').map { |turn| turn[:content] }).to eq(%w[oi olá])
  end

  it 'keeps conversations apart' do
    store.save('uma', turns)

    expect(store.load('outra')).to be_empty
  end

  it 'replaces what was there on the next save' do
    store.save('sessao', turns)
    store.save('sessao', [{ role: 'user', content: 'de novo' }])

    expect(store.load('sessao').size).to eq(1)
  end

  it 'clears a conversation' do
    store.save('sessao', turns)
    store.clear('sessao')

    expect(store.load('sessao')).to be_empty
  end

  it 'clears a conversation that does not exist without complaining' do
    expect { store.clear('nunca-existiu') }.not_to raise_error
  end
end
