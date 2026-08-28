# frozen_string_literal: true

require_relative '../lib/plan_and_solve_agent'

RSpec.describe PlanAndSolveAgent do
  def agent_for(llm, executor, **options)
    described_class.new(llm: llm, executor: executor, **options)
  end

  let(:plan) { "1. Buscar a política de férias.\n2. Contar os dias." }
  let(:llm) { ScriptedLlm.new(plan, 'São trinta dias por ano.') }
  let(:executor) { ScriptedExecutor.new('a política concede trinta dias', 'trinta') }

  describe 'planning' do
    it 'asks the model for a plan before doing anything' do
      agent_for(llm, executor).run('quantos dias de férias?')

      expect(llm.prompts.first).to include('quantos dias de férias?')
      expect(llm.prompts.first).to include('plano')
    end

    it 'records the plan it followed' do
      result = agent_for(llm, executor).run('quantos dias?')

      expect(result[:plan]).to eq(['Buscar a política de férias.', 'Contar os dias.'])
    end

    # Um plano de vinte passos custa vinte execuções, cada uma com suas próprias
    # chamadas de modelo. O teto é o que separa isso de uma conta surpresa.
    it 'cuts the plan down to the step limit' do
      long = (1..5).map { |number| "#{number}. passo #{number}" }.join("\n")
      result = agent_for(ScriptedLlm.new(long, 'pronto'), executor, max_steps: 2).run('?')

      expect(result[:plan].size).to eq(2)
      expect(executor.tasks.size).to eq(2)
    end

    # Prosa não é plano, mas também não é motivo para desistir: a pergunta
    # sozinha já é uma tarefa executável.
    it 'falls back to the question itself when the model wrote no plan' do
      result = agent_for(ScriptedLlm.new('acho melhor buscar na política', 'pronto'), executor).run('quantos dias?')

      expect(result[:plan]).to eq(['quantos dias?'])
      expect(executor.tasks.size).to eq(1)
    end
  end

  describe 'solving' do
    it 'sends each step of the plan to the executor' do
      agent_for(llm, executor).run('quantos dias?')

      expect(executor.tasks.first).to include('Buscar a política de férias.')
      expect(executor.tasks.last).to include('Contar os dias.')
    end

    it 'keeps the original question in every task' do
      agent_for(llm, executor).run('quantos dias de férias?')

      expect(executor.tasks).to all(include('quantos dias de férias?'))
    end

    # Sem isso, um passo que depende do anterior recomeça do zero e o plano
    # deixa de ser um plano.
    it 'carries what was already found into the next task' do
      agent_for(llm, executor).run('quantos dias?')

      expect(executor.tasks.last).to include('a política concede trinta dias')
    end

    it 'does not tell the first task about results that do not exist yet' do
      agent_for(llm, executor).run('quantos dias?')

      expect(executor.tasks.first).not_to include('trinta dias')
    end

    # O mesmo motivo do ReAct: sem o trajeto guardado não há como auditar por
    # que o agente respondeu o que respondeu.
    it 'keeps the trace the executor produced inside each step' do
      detailed = ScriptedExecutor.new({ answer: 'trinta', steps: [{ tool: 'buscar_documentos' }] })
      result = agent_for(llm, detailed).run('quantos dias?')

      expect(result[:steps].first[:trace]).to eq([{ tool: 'buscar_documentos' }])
    end

    it 'records the task and the result of each step' do
      result = agent_for(llm, executor).run('quantos dias?')

      expect(result[:steps].first).to include(task: 'Buscar a política de férias.',
                                              answer: 'a política concede trinta dias',
                                              finished: true)
    end
  end

  describe 'answering' do
    it 'answers with what the model wrote after seeing the steps' do
      expect(agent_for(llm, executor).run('quantos dias?')[:answer]).to eq('São trinta dias por ano.')
    end

    it 'shows the result of every step to the model before it answers' do
      agent_for(llm, executor).run('quantos dias?')

      expect(llm.prompts.last).to include('a política concede trinta dias').and include('trinta')
    end

    it 'marks the run as finished when every step concluded' do
      expect(agent_for(llm, executor).run('quantos dias?')[:finished]).to be(true)
    end

    it 'marks the run as unfinished when a step did not conclude' do
      halfway = ScriptedExecutor.new({ answer: 'não deu', finished: false }, 'trinta')

      expect(agent_for(llm, halfway).run('quantos dias?')[:finished]).to be(false)
    end

    # Passo que não concluiu e passo que concluiu não podem chegar iguais ao
    # modelo, senão ele preenche a lacuna com invenção.
    it 'flags the steps that did not conclude when asking for the answer' do
      halfway = ScriptedExecutor.new({ answer: 'não deu', finished: false }, 'trinta')
      agent_for(llm, halfway).run('quantos dias?')

      expect(llm.prompts.last).to include(described_class::UNFINISHED_MARK)
    end
  end
end
