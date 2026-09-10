# frozen_string_literal: true

require_relative 'prompt_builder'
require_relative 'prompt_compressor'
require_relative 'relevance_floor'
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
  NO_USAGE = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0, measured: false }.freeze
  NO_CONTEXT_ANSWER = 'Não encontrei essa informação nos documentos indexados.'

  def initialize(retriever:, llm:, collection:, prompt_builder: PromptBuilder.new, top_k: DEFAULT_TOP_K,
                 reranker: nil, compressor: nil, context_budget: nil, counter: TokenCounter.new,
                 tracer: Tracer.null, relevance_floor: nil)
    @retriever = retriever
    @llm = llm
    @collection = collection
    @prompt_builder = prompt_builder
    @counter = counter
    @tracer = tracer

    shape_retrieval(top_k, reranker, relevance_floor, compressor, context_budget)
  end

  def answer(question, filter: nil)
    @tracer.trace('rag.answer', input: question, metadata: model_metadata) do |span|
      answer_within(span, question, filter)
    end
  end

  private

  # Os cinco que decidem o que chega ao prompt, separados dos que dizem o que o
  # pipeline é. Todos opcionais: sem nenhum deles a recuperação é o top-k cru,
  # que é como este pipeline começou.
  def shape_retrieval(top_k, reranker, relevance_floor, compressor, context_budget)
    @top_k = top_k
    @reranker = reranker
    @relevance_floor = relevance_floor
    @compressor = compressor
    @context_budget = context_budget
  end

  # O nome do modelo vai no trace para que tokens e custo saiam rotulados por
  # modelo, e não num balde "desconhecido". Modelo que não se identifica não
  # quebra nada: fica sem rótulo, como sempre foi.
  def model_metadata
    @llm.respond_to?(:model) ? { model: @llm.model } : {}
  end

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
      text, usage = text_and_usage(prompt)
      generation.output = text
      generation.usage = usage

      [text, usage]
    end
  end

  # O uso medido pelo provedor ganha do estimado sempre que existe. A pergunta
  # é por capacidade, não por classe: o `AnthropicLlm` sabe informar, o
  # `ExtractiveLlm` não sabe e nem teria o que informar, e quem chama não
  # precisa saber qual é qual.
  #
  # `complete_with_usage` pode devolver `nil` no uso quando a resposta veio sem
  # o bloco de contagem; aí a estimativa volta a valer, e o `measured: false`
  # diz isso a quem for ler.
  def text_and_usage(prompt)
    unless @llm.respond_to?(:complete_with_usage)
      text = @llm.complete(prompt)
      return [text, usage_of(prompt, text)]
    end

    text, usage = @llm.complete_with_usage(prompt)

    [text, usage || usage_of(prompt, text)]
  end

  # Com reranker, recupera um pool maior e deixa a reordenação escolher os
  # top_k: reordenar só o que já cabia no contexto não mudaria nada.
  #
  # O piso vem por último, depois de recuperar e reordenar, porque é a única
  # etapa que pode devolver menos do que pediram — inclusive nada. As
  # anteriores escolhem *quais* dos trechos entram; ele decide se algum
  # merece entrar.
  def retrieve(question, filter:)
    hits = @retriever.search(question, collection: @collection, limit: retrieval_limit, filter: filter) || []
    hits = @reranker.rerank(question, hits, limit: @top_k) if @reranker
    passages = hits.filter_map { |hit| to_passage(hit) }

    @relevance_floor ? @relevance_floor.apply(question, passages) : passages
  end

  # Encaixa o contexto no orçamento de tokens antes de montar o prompt.
  def compress(passages)
    return passages unless @compressor && @context_budget

    @compressor.compress(passages, budget: @context_budget)
  end

  # `measured: false` viaja junto com o número, e não só na documentação: quem
  # lê uma conta de dinheiro precisa saber se ela veio do provedor ou da
  # heurística de ~4 caracteres por token do `TokenCounter`. A chave existe
  # sempre, com um valor ou outro, porque esquema estável é o que deixa filtrar
  # sem tratar ausência como caso à parte — mesmo motivo do `reason` na linha
  # de log da partida.
  def usage_of(prompt, answer)
    prompt_tokens = @counter.estimate(prompt)
    completion_tokens = @counter.estimate(answer)

    { prompt_tokens: prompt_tokens, completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens, measured: false }
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
