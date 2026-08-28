# frozen_string_literal: true

require_relative '../lib/state_graph'

RSpec.describe StateGraph do
  subject(:graph) { described_class.new }

  # Grafo mínimo: um nó que escreve algo e termina.
  def single_node(&block)
    graph.node(:passo, &block).edge(:passo, StateGraph::FINISH).entry(:passo)
  end

  describe 'running a node' do
    it 'returns the state the node produced' do
      single_node { { resposta: 'oi' } }

      expect(graph.run[:state]).to eq(resposta: 'oi')
    end

    # Nó devolve o que mudou, não o estado inteiro. Se substituísse, um nó
    # distraído apagaria em silêncio o trabalho dos anteriores.
    it 'merges the update into the state instead of replacing it' do
      single_node { { resposta: 'oi' } }

      expect(graph.run(pergunta: 'tudo bem?')[:state]).to eq(pergunta: 'tudo bem?', resposta: 'oi')
    end

    it 'hands the current state to the node' do
      seen = nil
      single_node { |state| seen = state and {} }
      graph.run(pergunta: 'tudo bem?')

      expect(seen).to eq(pergunta: 'tudo bem?')
    end

    it 'leaves the state untouched when the node returns nothing' do
      single_node { nil }

      expect(graph.run(pergunta: 'oi')[:state]).to eq(pergunta: 'oi')
    end

    it 'refuses an update that is not a hash' do
      single_node { 'oi' }

      expect { graph.run }.to raise_error(StateGraph::InvalidUpdateError, /passo/)
    end
  end

  describe 'walking the edges' do
    before do
      graph.node(:um) { { trilha: 'um' } }
      graph.node(:dois) { |state| { trilha: "#{state[:trilha]}-dois" } }
      graph.edge(:um, :dois).edge(:dois, StateGraph::FINISH).entry(:um)
    end

    it 'follows the edge to the next node' do
      expect(graph.run[:state][:trilha]).to eq('um-dois')
    end

    # Sem o caminho registrado não há como explicar por que o grafo parou onde
    # parou — o mesmo motivo do trajeto do agente ReAct.
    it 'records the path it walked' do
      expect(graph.run[:path]).to eq(%i[um dois])
    end

    it 'counts the steps it took' do
      expect(graph.run[:steps]).to eq(2)
    end

    it 'marks the run as finished when it reaches the end' do
      expect(graph.run[:finished]).to be(true)
    end
  end

  describe 'branching' do
    before do
      graph.node(:decidir) { |state| { tentativas: state[:tentativas].to_i + 1 } }
      graph.node(:refazer) { {} }
      graph.branch(:decidir) { |state| state[:tentativas] >= 2 ? StateGraph::FINISH : :refazer }
      graph.edge(:refazer, :decidir).entry(:decidir)
    end

    it 'picks the next node from the state' do
      expect(graph.run[:path]).to eq(%i[decidir refazer decidir])
    end

    it 'stops when the branch says the run is over' do
      expect(graph.run[:finished]).to be(true)
    end

    it 'refuses a branch that points at a node that does not exist' do
      graph.branch(:decidir) { :inexistente }

      expect { graph.run }.to raise_error(StateGraph::UnknownNodeError, /inexistente/)
    end
  end

  # Ciclo é o motivo de existir um grafo de estado em vez de uma lista de
  # passos. Sem teto, um ciclo que nunca fecha trava o processo.
  describe 'the step limit' do
    subject(:graph) { described_class.new(max_steps: 3) }

    before do
      graph.node(:eterno) { {} }
      graph.edge(:eterno, :eterno).entry(:eterno)
    end

    it 'stops at the limit' do
      expect(graph.run[:steps]).to eq(3)
    end

    it 'says out loud that it did not finish' do
      expect(graph.run[:finished]).to be(false)
    end
  end

  # Erro de montagem aparece na montagem, não no meio de uma corrida — nem só
  # no dia em que o ramo torto for percorrido pela primeira vez.
  describe 'checking the graph makes sense' do
    it 'refuses two nodes with the same name' do
      graph.node(:passo) { {} }

      expect { graph.node(:passo) { {} } }.to raise_error(ArgumentError, /passo/)
    end

    it 'refuses a node without a handler' do
      expect { graph.node(:passo) }.to raise_error(ArgumentError, /passo/)
    end

    it 'refuses an edge that leaves a node that does not exist' do
      expect { graph.edge(:fantasma, StateGraph::FINISH) }.to raise_error(StateGraph::UnknownNodeError, /fantasma/)
    end

    it 'refuses an edge that arrives at a node that does not exist' do
      graph.node(:passo) { {} }

      expect { graph.edge(:passo, :fantasma) }.to raise_error(StateGraph::UnknownNodeError, /fantasma/)
    end

    it 'refuses an entry point that does not exist' do
      expect { graph.entry(:fantasma) }.to raise_error(StateGraph::UnknownNodeError, /fantasma/)
    end

    it 'refuses to run without an entry point' do
      graph.node(:passo) { {} }
      graph.edge(:passo, StateGraph::FINISH)

      expect { graph.run }.to raise_error(StateGraph::InvalidGraphError, /entrada/)
    end

    # Esquecer a aresta de saída é o erro de montagem mais comum. Terminar em
    # silêncio esconderia isso; a conferência acontece antes do primeiro nó.
    it 'refuses to run when some node has no way out' do
      graph.node(:passo) { {} }
      graph.node(:esquecido) { {} }
      graph.edge(:passo, StateGraph::FINISH).entry(:passo)

      expect { graph.run }.to raise_error(StateGraph::InvalidGraphError, /esquecido/)
    end
  end

  it 'chains the building calls' do
    expect(graph.node(:passo) { {} }).to be(graph)
  end

  # Instrumentar aqui dá o rastro de qualquer coisa montada sobre o grafo —
  # o time multi-agente inclusive — sem instrumentar cada uma delas.
  describe 'tracing' do
    let(:exporter) { CollectingExporter.new }
    let(:tracer) { Tracer.new(exporter: exporter) }

    subject(:graph) { described_class.new(tracer: tracer, name: 'fluxo') }

    before do
      graph.node(:um) { { trilha: 'um' } }
      graph.node(:dois) { { trilha: 'dois' } }
      graph.edge(:um, :dois).edge(:dois, StateGraph::FINISH).entry(:um)
    end

    it 'exports one trace per run' do
      graph.run

      expect(exporter.traces.size).to eq(1)
    end

    it 'names the trace after the graph' do
      graph.run

      expect(exporter.last[:name]).to eq('fluxo')
    end

    it 'opens one span per node, named after it, in the order they ran' do
      graph.run

      expect(exporter.last[:spans].map { |span| span[:name] }).to eq(%w[um dois])
    end

    # Num ciclo o mesmo nó aparece várias vezes; sem o número do passo os spans
    # ficam indistinguíveis.
    it 'numbers the step each span belongs to' do
      graph.run

      expect(exporter.last[:spans].map { |span| span[:metadata][:step] }).to eq([1, 2])
    end

    it 'records what the node changed as the output of its span' do
      graph.run

      expect(exporter.last[:spans].first[:output]).to eq(trilha: 'um')
    end

    it 'annotates the path and how the run ended' do
      graph.run

      expect(exporter.last[:metadata]).to include(path: %i[um dois], finished: true)
    end

    # O nó que quebrou é o que se procura no visualizador.
    it 'marks the span of the node that blew up' do
      graph.node(:quebrado) { raise 'sem conexão' }
      graph.edge(:dois, :quebrado).edge(:quebrado, StateGraph::FINISH)

      begin
        graph.run
      rescue StandardError
        nil
      end

      expect(exporter.last[:spans].last[:name]).to eq('quebrado')
      expect(exporter.last[:spans].last[:status]).to eq(:error)
    end
  end
end
