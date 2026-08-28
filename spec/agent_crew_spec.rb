# frozen_string_literal: true

require_relative '../lib/agent_crew'

RSpec.describe AgentCrew do
  let(:rh_agent) { ScriptedExecutor.new('trinta dias', 'trinta dias corridos') }
  let(:infra_agent) { ScriptedExecutor.new('reinicia toda madrugada') }

  let(:specialists) do
    ToolRegistry.new(
      [SpecialistTool.build(name: 'rh', description: 'Sabe de férias e benefícios.', agent: rh_agent),
       SpecialistTool.build(name: 'infra', description: 'Sabe de servidores.', agent: infra_agent)]
    )
  end

  def crew_for(*responses, **options)
    described_class.new(llm: ScriptedLlm.new(*responses), specialists: specialists, **options)
  end

  describe 'routing' do
    it 'shows the specialists to the model before it chooses' do
      llm = ScriptedLlm.new('rh', 'aprovado')
      described_class.new(llm: llm, specialists: specialists).run('quantos dias de férias?')

      expect(llm.prompts.first).to include('Sabe de férias e benefícios.').and include('Sabe de servidores.')
    end

    it 'includes the question in the routing prompt' do
      llm = ScriptedLlm.new('rh', 'aprovado')
      described_class.new(llm: llm, specialists: specialists).run('quantos dias de férias?')

      expect(llm.prompts.first).to include('quantos dias de férias?')
    end

    it 'routes to the specialist the model named' do
      expect(crew_for('infra', 'aprovado').run('quando reinicia?')[:specialist]).to eq('infra')
    end

    # O modelo raramente responde só o nome. Achar o nome dentro da frase custa
    # menos do que exigir um formato que ele não vai seguir.
    it 'finds the name inside a sentence' do
      expect(crew_for('Acho que o infra resolve isso.', 'aprovado').run('?')[:specialist]).to eq('infra')
    end

    # Nome inventado não pode parar o time: alguém precisa atender.
    it 'falls back to the first specialist when the model named nobody known' do
      expect(crew_for('sei lá', 'aprovado').run('?')[:specialist]).to eq('rh')
    end

    it 'records that the routing had to fall back' do
      expect(crew_for('sei lá', 'aprovado').run('?')[:routed]).to be(false)
    end

    it 'records a routing that worked' do
      expect(crew_for('rh', 'aprovado').run('?')[:routed]).to be(true)
    end
  end

  describe 'executing' do
    it 'gives the question to the chosen specialist as the task' do
      crew_for('rh', 'aprovado').run('quantos dias de férias?')

      expect(rh_agent.tasks.first).to include('quantos dias de férias?')
    end

    it 'answers with what the specialist produced' do
      expect(crew_for('rh', 'aprovado').run('?')[:answer]).to eq('trinta dias')
    end
  end

  describe 'reviewing' do
    it 'shows the answer to the reviewer' do
      llm = ScriptedLlm.new('rh', 'aprovado')
      described_class.new(llm: llm, specialists: specialists).run('?')

      expect(llm.prompts.last).to include('trinta dias')
    end

    it 'accepts the answer on the first attempt when the review approves' do
      result = crew_for('rh', 'aprovado').run('?')

      expect(result[:approved]).to be(true)
      expect(result[:attempts]).to eq(1)
    end

    # Refazer sem saber o que estava errado é refazer igual.
    it 'sends the work back with the feedback of the review' do
      crew_for('rh', 'faltou dizer se são corridos', 'aprovado', max_attempts: 2).run('quantos dias?')

      expect(rh_agent.tasks.last).to include('faltou dizer se são corridos')
    end

    it 'answers with the reworked version' do
      result = crew_for('rh', 'faltou dizer se são corridos', 'aprovado', max_attempts: 2).run('?')

      expect(result[:answer]).to eq('trinta dias corridos')
      expect(result[:attempts]).to eq(2)
    end

    it 'records every review it received' do
      result = crew_for('rh', 'faltou dizer se são corridos', 'aprovado', max_attempts: 2).run('?')

      expect(result[:reviews]).to eq(['faltou dizer se são corridos', 'aprovado'])
    end

    # Revisor exigente sem teto refaz para sempre, e cada volta é um agente
    # inteiro rodando.
    it 'stops at the attempt limit and says the answer was not approved' do
      result = crew_for('rh', 'ruim', 'ruim ainda', max_attempts: 2).run('?')

      expect(result[:approved]).to be(false)
      expect(result[:attempts]).to eq(2)
    end

    # "não aprovado" contém "aprovado": procurar a palavra em qualquer lugar do
    # texto tomaria uma reprovação por aprovação.
    it 'does not take a rejection for an approval' do
      expect(crew_for('rh', 'não aprovado, faltou fonte', 'aprovado', max_attempts: 2).run('?')[:attempts]).to eq(2)
    end
  end

  it 'records the path it walked through the graph' do
    expect(crew_for('rh', 'aprovado').run('?')[:path]).to eq(%i[rotear executar revisar])
  end

  # O time não instrumenta nada por conta própria: o rastro vem do grafo em que
  # ele é montado.
  describe 'tracing' do
    let(:exporter) { CollectingExporter.new }

    it 'traces every node of the walk' do
      described_class.new(llm: ScriptedLlm.new('rh', 'aprovado'), specialists: specialists,
                          tracer: Tracer.new(exporter: exporter)).run('?')

      expect(exporter.last[:spans].map { |span| span[:name] }).to eq(%w[rotear executar revisar])
    end
  end
end
