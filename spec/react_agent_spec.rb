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

  # Instrumentação nasce desligada: o tracer padrão é o nulo.
  describe 'tracing' do
    let(:exporter) { CollectingExporter.new }
    let(:tracer) { Tracer.new(exporter: exporter) }

    def traced_agent(*responses)
      described_class.new(llm: ScriptedLlm.new(*responses), tools: tools, tracer: tracer)
    end

    def span_names
      exporter.last[:spans].map { |span| span[:name] }
    end

    it 'exports one trace per run' do
      traced_agent('Resposta Final: ok').run('?')

      expect(exporter.traces.size).to eq(1)
    end

    it 'records the question as the input and the answer as the output' do
      traced_agent('Resposta Final: são 30 dias.').run('Quantos dias?')

      expect(exporter.last[:input]).to eq('Quantos dias?')
      expect(exporter.last[:output]).to eq('são 30 dias.')
    end

    # A pergunta que a instrumentação existe para responder: o tempo foi no
    # modelo ou na ferramenta?
    it 'separates the model call from the tool call' do
      traced_agent("Ação: buscar\nEntrada: férias", 'Resposta Final: são 30 dias.').run('?')

      expect(span_names).to eq(%w[react.llm react.tool react.llm])
    end

    it 'opens no tool span when the model answered straight away' do
      traced_agent('Resposta Final: ok').run('?')

      expect(span_names).to eq(['react.llm'])
    end

    it 'keeps the observation as the output of the tool span' do
      traced_agent("Ação: buscar\nEntrada: férias", 'Resposta Final: ok').run('?')

      expect(exporter.last[:spans][1][:output]).to eq('A política concede 30 dias de férias.')
    end

    # Sem o número do turno, dois spans iguais no meio de um laço não dizem em
    # qual volta o agente estava.
    it 'numbers the turn each span belongs to' do
      traced_agent("Ação: buscar\nEntrada: férias", 'Resposta Final: ok').run('?')

      expect(exporter.last[:spans].map { |span| span[:metadata][:turn] }).to eq([1, 1, 2])
    end

    it 'names the tool on the tool span' do
      traced_agent("Ação: buscar\nEntrada: férias", 'Resposta Final: ok').run('?')

      expect(exporter.last[:spans][1][:metadata]).to include(tool: 'buscar')
    end

    it 'annotates how the run ended' do
      traced_agent('Resposta Final: ok').run('?')

      expect(exporter.last[:metadata]).to include(iterations: 1, finished: true)
    end

    it 'does not change the answer' do
      expect(traced_agent('Resposta Final: ok').run('?')[:answer]).to eq('ok')
    end
  end
end
