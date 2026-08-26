# frozen_string_literal: true

require_relative 'prompt_builder'

# RAG básico: recupera os trechos mais relevantes, monta o prompt com esse
# contexto e gera a resposta.
#
# O recuperador (`EtlPipeline`, por exemplo) e o modelo são injetados. O modelo
# precisa responder a `complete(prompt)` e devolver a resposta em texto.
class RagPipeline
  DEFAULT_TOP_K = 4
  NO_CONTEXT_ANSWER = 'Não encontrei essa informação nos documentos indexados.'

  def initialize(retriever:, llm:, collection:, prompt_builder: PromptBuilder.new, top_k: DEFAULT_TOP_K)
    @retriever = retriever
    @llm = llm
    @collection = collection
    @prompt_builder = prompt_builder
    @top_k = top_k
  end

  def answer(question, filter: nil)
    passages = retrieve(question, filter: filter)
    return empty_result(question) if passages.empty?

    prompt = @prompt_builder.build(question, passages)

    { question: question, answer: @llm.complete(prompt), passages: passages,
      sources: passages.filter_map { |passage| passage[:source] }.uniq, prompt: prompt }
  end

  private

  def retrieve(question, filter:)
    hits = @retriever.search(question, collection: @collection, limit: @top_k, filter: filter) || []

    hits.filter_map { |hit| to_passage(hit) }
  end

  def to_passage(hit)
    payload = hit[:payload] || {}
    return nil if payload[:text].nil? || payload[:text].empty?

    { text: payload[:text], source: payload[:source], score: hit[:score] }
  end

  # Sem contexto não há o que responder: economiza a chamada ao modelo.
  def empty_result(question)
    { question: question, answer: NO_CONTEXT_ANSWER, passages: [], sources: [], prompt: nil }
  end
end
