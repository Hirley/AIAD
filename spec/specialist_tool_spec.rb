# frozen_string_literal: true

require_relative '../lib/specialist_tool'

RSpec.describe SpecialistTool do
  let(:agent) { ScriptedExecutor.new('trinta dias por ano') }

  subject(:tool) do
    described_class.build(name: 'rh', description: 'Sabe de férias, ponto e benefícios.', agent: agent)
  end

  it 'builds a tool with the name of the specialist' do
    expect(tool.name).to eq('rh')
  end

  # A descrição é o único texto que o roteador lê para escolher a quem mandar.
  it 'keeps the description in the catalog signature' do
    expect(tool.signature).to include('Sabe de férias, ponto e benefícios.')
  end

  it 'hands the task to the agent' do
    tool.call(tarefa: 'quantos dias de férias?')

    expect(agent.tasks).to eq(['quantos dias de férias?'])
  end

  it 'answers with what the agent produced' do
    expect(tool.call(tarefa: 'quantos dias?')).to eq('trinta dias por ano')
  end

  # O agente pode não concluir. Devolver a resposta vazia esconderia isso de
  # quem revisa; o aviso vai junto, escrito.
  it 'says out loud when the agent did not conclude' do
    unfinished = ScriptedExecutor.new({ answer: 'não deu', finished: false })
    tool = described_class.build(name: 'rh', description: 'Sabe de RH.', agent: unfinished)

    expect(tool.call(tarefa: '?')).to include(described_class::UNFINISHED_MARK)
  end
end
