# frozen_string_literal: true

require 'tmpdir'
require_relative '../lib/file_conversation_store'

RSpec.describe FileConversationStore do
  around do |example|
    Dir.mktmpdir { |directory| @directory = directory and example.run }
  end

  subject(:store) { described_class.new(@directory) }

  it_behaves_like 'a conversation store'

  # O motivo de existir: a conversa continua depois de o processo morrer.
  it 'survives a brand new store over the same directory' do
    store.save('sessao', [{ role: 'user', content: 'oi' }])

    expect(described_class.new(@directory).load('sessao').first[:content]).to eq('oi')
  end

  it 'creates the directory when it is not there yet' do
    nested = File.join(@directory, 'conversas')
    described_class.new(nested).save('sessao', [{ role: 'user', content: 'oi' }])

    expect(Dir.exist?(nested)).to be(true)
  end

  # O id vem de fora. Sem higienizar, um id com "../" escreveria fora do
  # diretório da aplicação.
  it 'keeps an id that would escape the directory inside it' do
    store.save('../fora', [{ role: 'user', content: 'oi' }])

    expect(Dir.children(@directory).size).to eq(1)
    expect(store.load('../fora').first[:content]).to eq('oi')
  end

  it 'does not confuse two ids that sanitize to the same name' do
    store.save('a/b', [{ role: 'user', content: 'primeiro' }])
    store.save('a-b', [{ role: 'user', content: 'segundo' }])

    expect(store.load('a/b').first[:content]).to eq('primeiro')
  end
end
