# frozen_string_literal: true

require_relative '../lib/conversational_agent'

RSpec.describe ConversationalAgent do
  let(:inner) { ScriptedExecutor.new('trinta dias por ano.', 'cerca de quatro semanas.') }
  let(:memory) { ConversationMemory.new }

  subject(:agent) { described_class.new(agent: inner, memory: memory) }

  describe 'the first question' do
    it 'answers with what the agent produced' do
      expect(agent.ask('sessao', 'quantos dias de férias?')[:answer]).to eq('trinta dias por ano.')
    end

    it 'gives the question to the agent' do
      agent.ask('sessao', 'quantos dias de férias?')

      expect(inner.tasks.first).to include('quantos dias de férias?')
    end

    # Anunciar um histórico vazio só convida o modelo a inventar o que deveria
    # estar nele.
    it 'does not announce a history that does not exist yet' do
      agent.ask('sessao', 'quantos dias de férias?')

      expect(inner.tasks.first).not_to include(described_class::HISTORY_HEADING)
    end
  end

  describe 'the questions after that' do
    before { agent.ask('sessao', 'quantos dias de férias?') }

    # É todo o ponto da memória: "e em semanas?" não quer dizer nada sozinha.
    it 'shows the earlier turns to the agent' do
      agent.ask('sessao', 'e em semanas?')

      expect(inner.tasks.last).to include('trinta dias por ano.')
    end

    it 'still sends the new question' do
      agent.ask('sessao', 'e em semanas?')

      expect(inner.tasks.last).to include('e em semanas?')
    end

    it 'answers using the agent of the new turn' do
      expect(agent.ask('sessao', 'e em semanas?')[:answer]).to eq('cerca de quatro semanas.')
    end
  end

  describe 'the memory it leaves behind' do
    it 'records the question and the answer' do
      agent.ask('sessao', 'quantos dias de férias?')

      expect(memory.turns('sessao')).to eq([{ role: :user, content: 'quantos dias de férias?' },
                                            { role: :assistant, content: 'trinta dias por ano.' }])
    end

    # Guardar "não concluí" é honesto; apagar faria a próxima pergunta achar
    # que o assunto foi resolvido.
    it 'records an answer that did not conclude' do
      halfway = described_class.new(agent: ScriptedExecutor.new({ answer: 'não deu', finished: false }),
                                    memory: memory)
      halfway.ask('sessao', '?')

      expect(memory.turns('sessao').last[:content]).to eq('não deu')
    end

    it 'keeps conversations apart' do
      agent.ask('uma', 'quantos dias de férias?')

      expect(inner.tasks.last).not_to include('trinta dias')
      expect(memory.turns('outra')).to be_empty
    end

    it 'names the conversation in the result' do
      expect(agent.ask('sessao', '?')[:conversation]).to eq('sessao')
    end

    it 'passes the rest of the agent result through untouched' do
      expect(agent.ask('sessao', '?')[:finished]).to be(true)
    end
  end
end
