# frozen_string_literal: true

# Grafo de estado: nós que transformam um estado compartilhado e arestas que
# decidem quem roda em seguida. É o que LangGraph faz em Python, no tamanho que
# este projeto precisa.
#
# A diferença para uma lista de passos é o ciclo: o grafo pode voltar para um
# nó anterior quando o resultado não serviu — recuperar de novo com outra
# consulta, revisar uma resposta reprovada. Fluxo agêntico é cheio disso.
#
# Quatro decisões que definem o comportamento:
#
# - **O nó devolve o que mudou, não o estado inteiro.** A atualização é fundida
#   no estado. Se substituísse, um nó distraído apagaria em silêncio o trabalho
#   dos anteriores.
# - **Teto de passos.** Ciclo é o motivo de o grafo existir, e ciclo que não
#   fecha trava o processo. Batendo no teto a corrida devolve `finished: false`
#   com o estado até ali, em vez de rodar para sempre.
# - **Erro de montagem aparece na montagem.** Aresta para nó inexistente falha
#   na hora de declarar; nó sem saída e grafo sem entrada falham antes do
#   primeiro nó rodar, não no dia em que aquele ramo for percorrido.
# - **O caminho fica registrado.** Sem ele não há como explicar por que o grafo
#   parou onde parou.
class StateGraph
  class UnknownNodeError < StandardError; end
  class InvalidGraphError < StandardError; end
  class InvalidUpdateError < StandardError; end

  FINISH = :fim
  DEFAULT_MAX_STEPS = 25

  def initialize(max_steps: DEFAULT_MAX_STEPS)
    @max_steps = max_steps
    @nodes = {}
    @exits = {}
    @entry = nil
  end

  def node(name, handler = nil, &block)
    handler ||= block
    raise ArgumentError, "o nó #{name} já foi declarado" if @nodes.key?(name)
    raise ArgumentError, "o nó #{name} precisa de um bloco ou de um handler" unless handler.respond_to?(:call)

    @nodes[name] = handler
    self
  end

  # Saída fixa: depois de `from`, sempre `to`.
  def edge(from, to)
    known!(from)
    known!(to) unless to == FINISH

    @exits[from] = ->(_state) { to }
    self
  end

  # Saída condicional: o bloco olha o estado e escolhe o próximo nó (ou FINISH).
  def branch(from, &chooser)
    known!(from)

    @exits[from] = chooser
    self
  end

  def entry(name)
    known!(name)

    @entry = name
    self
  end

  def run(state = {})
    ready!
    walk(state)
  end

  private

  def walk(state)
    path = []
    current = @entry

    @max_steps.times do
      state = advance(current, state)
      path << current
      current = next_node(current, state)

      return finished(state, path) if current == FINISH
    end

    { state: state, path: path, steps: path.size, finished: false }
  end

  def finished(state, path)
    { state: state, path: path, steps: path.size, finished: true }
  end

  def advance(name, state)
    update = @nodes.fetch(name).call(state)
    return state if update.nil?
    raise InvalidUpdateError, "o nó #{name} devolveu #{update.class}, e não um Hash" unless update.is_a?(Hash)

    state.merge(update)
  end

  def next_node(name, state)
    target = @exits.fetch(name).call(state)
    return target if target == FINISH || @nodes.key?(target)

    raise UnknownNodeError, "o nó #{name} apontou para #{target}, que não existe"
  end

  def known!(name)
    raise UnknownNodeError, "o nó #{name} não existe" unless @nodes.key?(name)
  end

  def ready!
    raise InvalidGraphError, 'o grafo não tem ponto de entrada' if @entry.nil?

    orphans = @nodes.keys - @exits.keys
    return if orphans.empty?

    raise InvalidGraphError, "sem saída declarada: #{orphans.join(', ')}"
  end
end
