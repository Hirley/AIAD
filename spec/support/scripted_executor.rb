# frozen_string_literal: true

# Dublê do executor de passos do Plan-and-Solve, no lugar de um agente ReAct
# inteiro. Guarda a tarefa que recebeu, que é o que quase todo exemplo quer
# conferir: se o passo certo foi despachado e se o que já foi apurado chegou
# junto.
#
# Diferente do `ScriptedLlm`, acabar o roteiro aqui não é erro: o plano tem
# tamanho variável e obrigar cada exemplo a enumerar um resultado por passo
# só acrescentaria ruído a exemplos que não falam sobre isso.
class ScriptedExecutor
  DEFAULT_ANSWER = 'resultado do passo'

  attr_reader :tasks

  def initialize(*results)
    @results = results.flatten
    @tasks = []
  end

  def run(task)
    @tasks << task

    normalize(@results[@tasks.size - 1])
  end

  private

  def normalize(result)
    return { answer: DEFAULT_ANSWER, finished: true } if result.nil?
    return { answer: result, finished: true } if result.is_a?(String)

    { answer: DEFAULT_ANSWER, finished: true }.merge(result)
  end
end
