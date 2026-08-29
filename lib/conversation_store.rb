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
#
# **O número de conversas é limitado.** Isto aqui vive na memória de um processo
# que atende requisição: uma rota que cria uma sessão nova a cada pergunta sem
# `session` encheria o Hash até o processo morrer, e o vazamento só apareceria
# semanas depois, em produção, sem nada apontando para cá. Passado o teto, a
# conversa **menos recentemente usada** sai. É a escolha certa porque conversa
# velha é justamente a que ninguém vai continuar.
#
# O limite é de conversas, não de turnos: quanto histórico guardar é decisão da
# `ConversationMemory`, que é quem tem o conceito de turno. Aqui só se resolve
# o problema de memória que é desta classe.
class ConversationStore
  DEFAULT_MAX_SESSIONS = 500

  def initialize(max_sessions: DEFAULT_MAX_SESSIONS)
    @max_sessions = max_sessions
    @conversations = {}
  end

  def load(id)
    key = id.to_s
    return [] unless @conversations.key?(key)

    touch(key).map(&:dup)
  end

  def save(id, turns)
    key = id.to_s
    @conversations.delete(key)
    @conversations[key] = turns.map(&:dup)
    evict_oldest

    turns
  end

  def clear(id)
    @conversations.delete(id.to_s)
  end

  def size
    @conversations.size
  end

  private

  # Ler também conta como uso: uma conversa consultada agora não pode ser
  # descartada como se estivesse parada. O Hash do Ruby preserva a ordem de
  # inserção, então reinserir joga a conversa para o fim da fila — e a frente
  # da fila é, por construção, a menos recentemente usada.
  def touch(key)
    turns = @conversations.delete(key)
    @conversations[key] = turns
  end

  def evict_oldest
    @conversations.shift while @conversations.size > @max_sessions
  end
end
