# frozen_string_literal: true

require_relative '../lib/react_agent'

RSpec.describe ReactAgent do
  let(:policy) do
    Tool.new(name: 'buscar', description: 'Busca na política interna.', parameters: { termo: 'o texto' }) do |arguments|
      arguments[:termo].to_s.include?('férias') ? 'A política concede 30 dias de férias.' : 'Nada encontrado.'
    end
  end

  let(:tools) { ToolRegistry.new([policy]) }

  def agent_for(*responses, **options)
    described_class.new(llm: ScriptedLlm.new(*responses), tools: tools, **options)
  end

  describe '#run' do
    it 'answers straight away when the model does not need a tool' do
      result = agent_for('Resposta Final: bom dia!').run('Bom dia?')

      expect(result[:answer]).to eq('bom dia!')
    end

    it 'uses the tool result to answer' do
      result = agent_for(
        "Pensamento: preciso da política.\nAção: buscar\nEntrada: {\"termo\": \"férias\"}",
        'Resposta Final: são 30 dias.'
      ).run('Quantos dias de férias eu tenho?')

      expect(result[:answer]).to eq('são 30 dias.')
    end

    it 'records the trace of what it thought, did and observed' do
      result = agent_for(
        "Pensamento: preciso da política.\nAção: buscar\nEntrada: {\"termo\": \"férias\"}",
        'Resposta Final: são 30 dias.'
      ).run('Quantos dias?')

      expect(result[:steps].first).to include(
        thought: 'preciso da política.',
        tool: 'buscar',
        arguments: { termo: 'férias' },
        observation: 'A política concede 30 dias de férias.'
      )
    end

    it 'reports how many turns it took' do
      result = agent_for(
        "Ação: buscar\nEntrada: férias",
        'Resposta Final: são 30 dias.'
      ).run('Quantos dias?')

      expect(result[:iterations]).to eq(2)
    end

    it 'feeds the observation back so the next turn can use it' do
      llm = ScriptedLlm.new("Ação: buscar\nEntrada: férias", 'Resposta Final: são 30 dias.')
      described_class.new(llm: llm, tools: tools).run('Quantos dias?')

      expect(llm.prompts.last).to include('A política concede 30 dias de férias.')
    end

    it 'shows the tool catalog to the model' do
      llm = ScriptedLlm.new('Resposta Final: ok')
      described_class.new(llm: llm, tools: tools).run('Quantos dias?')

      expect(llm.prompts.first).to include('buscar(termo: o texto)')
    end

    it 'includes the question in the prompt' do
      llm = ScriptedLlm.new('Resposta Final: ok')
      described_class.new(llm: llm, tools: tools).run('Quantos dias de férias?')

      expect(llm.prompts.first).to include('Quantos dias de férias?')
    end
  end

  describe 'input handling' do
    it 'parses a JSON input into arguments' do
      result = agent_for("Ação: buscar\nEntrada: {\"termo\": \"férias\"}", 'Resposta Final: ok').run('?')

      expect(result[:steps].first[:arguments]).to eq(termo: 'férias')
    end

    # Modelo cerca JSON com crase por hábito de chat.
    it 'reads a JSON input wrapped in a code fence' do
      fenced = "Ação: buscar\nEntrada: ```json\n{\"termo\": \"férias\"}\n```"
      result = agent_for(fenced, 'Resposta Final: ok').run('?')

      expect(result[:steps].first[:arguments]).to eq(termo: 'férias')
    end

    # Modelo escreve texto solto o tempo todo. Com um único parâmetro não há
    # ambiguidade sobre onde ele vai, então aceitar é melhor do que reclamar.
    it 'wraps a plain-text input into the only parameter of the tool' do
      result = agent_for("Ação: buscar\nEntrada: férias", 'Resposta Final: ok').run('?')

      expect(result[:steps].first[:arguments]).to eq(termo: 'férias')
    end

    it 'refuses to guess where plain text goes when the tool takes several parameters' do
      two_params = Tool.new(name: 'somar', description: 'Soma.', parameters: { a: 'um', b: 'outro' }) { 'x' }
      agent = described_class.new(llm: ScriptedLlm.new("Ação: somar\nEntrada: 2 e 3", 'Resposta Final: ok'),
                                  tools: ToolRegistry.new([two_params]))

      expect(agent.run('?')[:steps].first[:observation]).to start_with('Erro')
    end

    it 'calls a no-argument tool with no arguments' do
      clock = Tool.new(name: 'relogio', description: 'Informa a hora.') { 'meio-dia' }
      agent = described_class.new(llm: ScriptedLlm.new('Ação: relogio', 'Resposta Final: ok'),
                                  tools: ToolRegistry.new([clock]))

      expect(agent.run('?')[:steps].first[:observation]).to eq('meio-dia')
    end
  end

  describe 'when things go wrong' do
    it 'turns a tool failure into an observation and keeps going' do
      broken = Tool.new(name: 'quebrada', description: 'Falha.') { raise 'sem conexão' }
      agent = described_class.new(llm: ScriptedLlm.new('Ação: quebrada', 'Resposta Final: não consegui consultar.'),
                                  tools: ToolRegistry.new([broken]))

      expect(agent.run('?')[:answer]).to eq('não consegui consultar.')
    end

    it 'nudges the model about the format instead of giving up on unreadable output' do
      agent = agent_for('bom dia, tudo bem?', 'Resposta Final: ok')

      expect(agent.run('?')[:steps].first[:observation]).to include('formato')
    end

    # Sem teto, um modelo teimoso chama ferramenta para sempre — e cada volta
    # custa uma chamada paga.
    it 'stops after the iteration limit' do
      responses = Array.new(3, "Ação: buscar\nEntrada: férias")

      expect(agent_for(*responses, max_iterations: 3).run('?')[:iterations]).to eq(3)
    end

    it 'says out loud that it did not conclude when it hits the limit' do
      responses = Array.new(3, "Ação: buscar\nEntrada: férias")
      result = agent_for(*responses, max_iterations: 3).run('?')

      expect(result[:finished]).to be(false)
      expect(result[:answer]).to include('Não consegui')
    end

    it 'marks a completed run as finished' do
      expect(agent_for('Resposta Final: ok').run('?')[:finished]).to be(true)
    end
  end
end
