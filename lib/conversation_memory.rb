# frozen_string_literal: true

require_relative 'conversation_store'
require_relative 'token_counter'

# Memória de conversa: guarda os turnos de cada sessão e devolve o pedaço do
# histórico que cabe no orçamento de tokens.
#
# Quatro decisões que definem o comportamento:
#
# - **O store é injetado.** Em memória por padrão, em disco quando a conversa
#   precisa sobreviver ao processo. Os dois cumprem o mesmo contrato, então a
#   troca não muda nada aqui.
# - **Papel é símbolo aqui, texto no store.** O store atravessa JSON, que não
#   tem símbolo, e não é dele o conceito de papel de conversa. A conversão
#   acontece só nesta classe.
# - **Orçamento de tokens no histórico, não no guardado.** Conversa cresce sem
#   parar e o histórico inteiro é pago em toda chamada, então `history` corta
#   os turnos mais antigos. O que foi dito continua inteiro em `turns`: cortar
#   o registro seria perder informação para economizar prompt.
# - **O turno mais recente nunca cai.** Se ele sozinho estoura o orçamento, ele
#   fica assim mesmo. Sem a última fala o histórico não serve para nada.
class ConversationMemory
  LABELS = { user: 'Usuário', assistant: 'Assistente' }.freeze
  DEFAULT_BUDGET = 400

  def initialize(store: ConversationStore.new, counter: TokenCounter.new, budget: DEFAULT_BUDGET)
    @store = store
    @counter = counter
    @budget = budget
  end

  def append(id, role:, content:)
    role!(role)
    @store.save(id, @store.load(id) + [{ role: role.to_s, content: content.to_s }])

    self
  end

  def turns(id)
    @store.load(id).map { |turn| { role: turn[:role].to_sym, content: turn[:content] } }
  end

  def history(id)
    within_budget(turns(id))
  end

  def transcript(id)
    history(id).map { |turn| "#{LABELS.fetch(turn[:role])}: #{turn[:content]}" }.join("\n")
  end

  def clear(id)
    @store.clear(id)

    self
  end

  private

  # Percorre de trás para frente: o que importa preservar é o fim da conversa.
  def within_budget(turns)
    remaining = @budget

    kept = turns.reverse.take_while do |turn|
      remaining -= @counter.estimate(turn[:content])
      remaining >= 0
    end

    kept.empty? ? turns.last(1) : kept.reverse
  end

  def role!(role)
    return if LABELS.key?(role)

    raise ArgumentError, "papel desconhecido: #{role}. Use #{LABELS.keys.join(' ou ')}."
  end
end
