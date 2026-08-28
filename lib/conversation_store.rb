# frozen_string_literal: true

# Guarda a conversa em memória, uma lista de turnos por id.
#
# É o padrão porque não exige nada do ambiente: teste, script e API rodam sem
# configurar disco. Some quando o processo morre — para sobreviver a isso,
# troque pelo `FileConversationStore`, que cumpre o mesmo contrato.
#
# O que sai de `load` é cópia. Devolver a lista interna deixaria quem chamou
# alterar a conversa guardada sem passar por `save`, e o store em disco nunca
# se comportaria assim: um dos dois estaria mentindo sobre o contrato.
class ConversationStore
  def initialize
    @conversations = {}
  end

  def load(id)
    @conversations.fetch(id.to_s, []).map(&:dup)
  end

  def save(id, turns)
    @conversations[id.to_s] = turns.map(&:dup)
  end

  def clear(id)
    @conversations.delete(id.to_s)
  end
end
