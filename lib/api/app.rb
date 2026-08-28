# frozen_string_literal: true

require 'json'

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

    def initialize(etl:, rag:, collection:)
      @etl = etl
      @rag = rag
      @collection = collection
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
