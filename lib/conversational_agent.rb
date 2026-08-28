# frozen_string_literal: true

require_relative 'conversation_memory'

# Dá memória a um agente que não tem: guarda a conversa, entrega o histórico
# junto da pergunta nova e registra o que foi respondido.
#
# É decorador, não classe-base: `ReactAgent`, `PlanAndSolveAgent` e `AgentCrew`
# entram aqui sem saber que existe memória. Um agente sozinho responde bem a
# "quantos dias de férias?" e não faz ideia do que fazer com "e em semanas?" —
# a diferença entre os dois é só o histórico chegar junto.
#
# Três decisões que definem o comportamento:
#
# - **Histórico vazio não vira seção vazia.** Anunciar um histórico que não
#   existe convida o modelo a inventar o que deveria estar nele.
# - **Quem corta o histórico é a memória.** O orçamento de tokens já está lá,
#   com a regra de derrubar o mais antigo primeiro.
# - **Resposta que não concluiu também é registrada.** Apagar faria a pergunta
#   seguinte achar que o assunto foi resolvido.
class ConversationalAgent
  HISTORY_HEADING = 'Conversa até aqui:'

  PROMPT = <<~PROMPT
    %<heading>s%<history>s
    %<question>s
  PROMPT

  def initialize(agent:, memory: ConversationMemory.new)
    @agent = agent
    @memory = memory
  end

  def ask(conversation, question)
    result = @agent.run(task_for(conversation, question))
    remember(conversation, question, result[:answer])

    result.merge(conversation: conversation)
  end

  private

  def task_for(conversation, question)
    history = @memory.transcript(conversation)
    return question if history.empty?

    format(PROMPT, heading: "#{HISTORY_HEADING}\n", history: "#{history}\n", question: question).strip
  end

  def remember(conversation, question, answer)
    @memory.append(conversation, role: :user, content: question)
    @memory.append(conversation, role: :assistant, content: answer)
  end
end
