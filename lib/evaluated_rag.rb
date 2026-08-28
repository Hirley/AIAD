# frozen_string_literal: true

require_relative 'answer_evaluator'
require_relative 'evaluation_log'
require_relative 'rag_pipeline'

# Avaliação contínua na frente do RAG: toda resposta é pontuada assim que sai, a
# nota vai junto no resultado e entra no log.
#
# É decorador, com a mesma interface do `RagPipeline`, pelo mesmo motivo do
# `CachedRag`: o pipeline não precisa saber que existe avaliação.
#
# A nota vai nos dois lugares de propósito. No resultado, para quem chamou poder
# decidir na hora — avisar o usuário, exigir revisão humana, recusar de vez. No
# log, para a média ao longo do tempo, que é o que mostra a qualidade caindo
# antes de alguém reclamar.
#
# Três decisões que definem o comportamento:
#
# - **Resposta sem contexto não é avaliada.** Quando nada foi recuperado, o
#   pipeline nem chama o modelo: não há o que alucinar. Pontuar zero aí encheria
#   o painel de falso positivo e afundaria a média por um acerto.
# - **Avaliador quebrado não derruba a resposta.** Mesma inversão do exportador
#   de trace: quem observa não pode derrubar quem faz. A resposta sai sem nota.
# - **A nota é sobre os trechos que o modelo recebeu**, não sobre o acervo
#   inteiro. Sustentação é "isso está no que ele leu"; se o trecho certo não foi
#   recuperado, o problema aparece na relevância de contexto, que é outra nota.
class EvaluatedRag
  def initialize(rag:, evaluator: AnswerEvaluator.new, log: EvaluationLog.new)
    @rag = rag
    @evaluator = evaluator
    @log = log
  end

  def answer(question, filter: nil)
    result = @rag.answer(question, filter: filter)
    scores = evaluate(result)

    scores ? result.merge(evaluation: scores) : result
  end

  private

  def evaluate(result)
    return nil if result[:passages].nil? || result[:passages].empty?

    scores = @evaluator.evaluate(question: result[:question], answer: result[:answer],
                                 passages: result[:passages])
    @log.record(question: result[:question], answer: result[:answer], scores: scores)

    scores
  rescue StandardError
    nil
  end
end
