# frozen_string_literal: true

require 'json'
require 'securerandom'

require_relative '../content_cleaner'
require_relative '../document_ingestor'
require_relative '../etl_pipeline'
require_relative '../rag_pipeline'
require_relative 'json_content_type'

module Api
  # API HTTP do assistente: ingestão de documentos, busca e pergunta com RAG.
  #
  # É um app Rack simples, sem framework: as rotas são poucas e explícitas. O
  # controle de acesso não está aqui — fica no middleware Authentication, para
  # que uma rota nova nasça protegida mesmo que se esqueça de tratá-la.
  class App
    FORMATS = ContentCleaner::FORMATS.map(&:to_s).freeze
    AGENT_UNAVAILABLE = 'rota de agente indisponível: configure ANTHROPIC_API_KEY para habilitá-la'

    # O agente é opcional: sem modelo de verdade configurado ele não existe, e
    # a rota diz isso em vez de fingir. O `ExtractiveLlm` não fala o formato
    # ReAct — montar o agente em cima dele daria seis voltas no laço para
    # devolver "não cheguei a uma conclusão", que é a pior forma de falhar:
    # devagar e sem explicar.
    def initialize(etl:, rag:, collection:, agent: nil)
      @etl = etl
      @rag = rag
      @collection = collection
      @agent = agent
    end

    def call(env)
      route(env['REQUEST_METHOD'], env['PATH_INFO'], env)
    rescue JSON::ParserError
      json(400, error: 'corpo da requisição não é JSON válido')
    rescue DocumentIngestor::BlankContentError, ContentCleaner::UnsupportedFormatError => e
      json(422, error: e.message)
    rescue QdrantClient::RequestError
      # A mensagem original carrega o caminho chamado no Qdrant; para quem
      # consome a API basta saber que a dependência falhou.
      json(503, error: 'serviço de busca temporariamente indisponível')
    end

    private

    def route(method, path, env)
      case [method, path]
      when %w[GET /health] then json(200, status: 'ok')
      when %w[POST /documents] then create_document(payload(env))
      when %w[POST /search] then search(payload(env))
      when %w[POST /ask] then ask(payload(env))
      when %w[POST /agent] then run_agent(payload(env))
      else json(404, error: "rota não encontrada: #{method} #{path}")
      end
    end

    def create_document(payload)
      missing = missing_fields(payload, %w[content source])
      return missing if missing

      format = payload.fetch('format', 'texto')
      return json(422, error: "formato não suportado: #{format}") unless FORMATS.include?(format)

      result = @etl.run(payload['content'], collection: @collection, source: payload['source'],
                                            format: format.to_sym, metadata: symbolize(payload['metadata']) || {})

      json(201, source: result[:source], chunks: result[:chunks], point_ids: result[:point_ids])
    end

    def search(payload)
      missing = missing_fields(payload, %w[query])
      return missing if missing

      hits = @etl.search(payload['query'], collection: @collection, limit: payload.fetch('limit', 10),
                                           filter: symbolize(payload['filter']))

      json(200, results: hits.map { |hit| present_hit(hit) })
    end

    def ask(payload)
      missing = missing_fields(payload, %w[question])
      return missing if missing

      result = @rag.answer(payload['question'], filter: symbolize(payload['filter']))

      # O prompt fica fora da resposta: é detalhe interno e pode carregar
      # trecho de documento que o cliente não pediu.
      json(200, answer: result[:answer], sources: result[:sources],
                passages: result[:passages].map { |passage| present_passage(passage) },
                cached: result[:cached], usage: result[:usage])
    end

    # A sessão identifica a conversa, e é ela que dá memória ao agente. Quando
    # não vem, uma é criada e devolvida: assim a primeira pergunta não precisa
    # saber que existe sessão, e a segunda já pode continuar de onde parou.
    def run_agent(payload)
      return json(503, error: AGENT_UNAVAILABLE) if @agent.nil?

      missing = missing_fields(payload, %w[question])
      return missing if missing

      session = presence(payload['session']) || SecureRandom.hex(8)

      present_agent(@agent.ask(session, payload['question']), session)
    end

    # O trajeto não volta inteiro. As observações são trechos de documento que
    # o cliente não pediu — mesmo motivo pelo qual o `/ask` não devolve o
    # prompt. O que volta é o que ajuda a confiar na resposta: quantas voltas
    # deu, se concluiu e em quais ferramentas se apoiou.
    def present_agent(result, session)
      json(200, answer: result[:answer], session: session, iterations: result[:iterations],
                finished: result[:finished], tools: result[:steps].to_a.filter_map { |step| step[:tool] }.uniq)
    end

    def presence(value)
      return nil unless value.is_a?(String)

      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    def present_hit(hit)
      payload = hit[:payload] || {}

      { id: hit[:id], score: hit[:score], source: payload[:source], text: payload[:text] }
    end

    def present_passage(passage)
      { source: passage[:source], score: passage[:score], text: passage[:text] }
    end

    def missing_fields(payload, required)
      absent = required.reject { |field| payload[field].is_a?(String) && !payload[field].strip.empty? }
      return nil if absent.empty?

      json(422, error: "campo obrigatório ausente: #{absent.join(', ')}")
    end

    def payload(env)
      body = env['rack.input'].read
      return {} if body.nil? || body.empty?

      parsed = JSON.parse(body)
      raise JSON::ParserError, 'corpo precisa ser um objeto JSON' unless parsed.is_a?(Hash)

      parsed
    end

    def symbolize(value)
      case value
      when Hash then value.to_h { |key, nested| [key.to_sym, symbolize(nested)] }
      when Array then value.map { |item| symbolize(item) }
      else value
      end
    end

    def json(status, body)
      [status, { 'content-type' => JSON_CONTENT_TYPE }, [JSON.generate(body)]]
    end
  end
end
