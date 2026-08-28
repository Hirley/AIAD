# frozen_string_literal: true

require_relative 'prompt_builder'
require_relative 'prompt_compressor'
require_relative 'reranker'
require_relative 'token_counter'
require_relative 'tracer'

# RAG básico: recupera os trechos mais relevantes, monta o prompt com esse
# contexto e gera a resposta.
#
# O recuperador (`EtlPipeline`, por exemplo) e o modelo são injetados. O modelo
# precisa responder a `complete(prompt)` e devolver a resposta em texto.
class RagPipeline
  DEFAULT_TOP_K = 4
  RERANK_POOL_FACTOR = 4
  NO_USAGE = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }.freeze
  NO_CONTEXT_ANSWER = 'Não encontrei essa informação nos documentos indexados.'

  def initialize(retriever:, llm:, collection:, prompt_builder: PromptBuilder.new, top_k: DEFAULT_TOP_K,
                 reranker: nil, compressor: nil, context_budget: nil, counter: TokenCounter.new,
                 tracer: Tracer.null)
    @retriever = retriever
    @llm = llm
    @collection = collection
    @prompt_builder = prompt_builder
    @top_k = top_k
    @reranker = reranker
    @compressor = compressor
    @context_budget = context_budget
    @counter = counter
    @tracer = tracer
  end

  def answer(question, filter: nil)
    @tracer.trace('rag.answer', input: question) { |span| answer_within(span, question, filter) }
  end

  private

  def answer_within(span, question, filter)
    passages = compress(span.span('rag.retrieve') { retrieve(question, filter: filter) })
    return empty_result(question) if passages.empty?

    prompt = @prompt_builder.build(question, passages)
    generated, usage = generate(span, prompt)

    { question: question, answer: generated, passages: passages,
      sources: passages.filter_map { |passage| passage[:source] }.uniq, prompt: prompt,
      cached: false, usage: usage }
  end

  # O uso é medido dentro do span e devolvido junto: quem monta a resposta
  # precisa dele, e ler de volta do span obrigaria o span nulo a guardar
  # estado só para isso.
  def generate(span, prompt)
    span.span('rag.generate', input: prompt) do |generation|
      text = @llm.complete(prompt)
      usage = usage_of(prompt, text)
      generation.output = text
      generation.usage = usage

      [text, usage]
    end
  end

  # Com reranker, recupera um pool maior e deixa a reordenação escolher os
  # top_k: reordenar só o que já cabia no contexto não mudaria nada.
  def retrieve(question, filter:)
    hits = @retriever.search(question, collection: @collection, limit: retrieval_limit, filter: filter) || []
    hits = @reranker.rerank(question, hits, limit: @top_k) if @reranker

    hits.filter_map { |hit| to_passage(hit) }
  end

  # Encaixa o contexto no orçamento de tokens antes de montar o prompt.
  def compress(passages)
    return passages unless @compressor && @context_budget

    @compressor.compress(passages, budget: @context_budget)
  end

  def usage_of(prompt, answer)
    prompt_tokens = @counter.estimate(prompt)
    completion_tokens = @counter.estimate(answer)

    { prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens }
  end

  def retrieval_limit
    @reranker ? @top_k * RERANK_POOL_FACTOR : @top_k
  end

  def to_passage(hit)
    payload = hit[:payload] || {}
    return nil if payload[:text].nil? || payload[:text].empty?

    { text: payload[:text], source: payload[:source], score: hit[:score] }
  end

  # Sem contexto não há o que responder: economiza a chamada ao modelo.
  def empty_result(question)
    { question: question, answer: NO_CONTEXT_ANSWER, passages: [], sources: [], prompt: nil,
      cached: false, usage: NO_USAGE }
  end
end
