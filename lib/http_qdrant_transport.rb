# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Transporte HTTP real para o Qdrant, no formato que o QdrantClient espera:
# responde a get/put/post/patch/delete e devolve um Hash com a chave :ok.
#
# Falha de rede e status fora da faixa 2xx viram `{ ok: false, ... }` em vez de
# exceção — quem decide o que fazer com o erro é o QdrantClient, que levanta
# RequestError. Assim o transporte continua sendo apenas transporte.
class HttpQdrantTransport
  DEFAULT_URL = 'http://localhost:6333'
  DEFAULT_OPEN_TIMEOUT = 2
  DEFAULT_READ_TIMEOUT = 10

  attr_reader :url

  def initialize(url: DEFAULT_URL, api_key: nil, open_timeout: DEFAULT_OPEN_TIMEOUT,
                 read_timeout: DEFAULT_READ_TIMEOUT, client: nil)
    @url = url
    @uri = URI.parse(url)
    @api_key = api_key
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @client = client
  end

  def self.from_env(env = ENV)
    new(url: env['QDRANT_URL'] || DEFAULT_URL, api_key: env['QDRANT_API_KEY'])
  end

  def get(path)
    request(Net::HTTP::Get, path, nil)
  end

  def put(path, body)
    request(Net::HTTP::Put, path, body)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body)
  end

  def patch(path, body)
    request(Net::HTTP::Patch, path, body)
  end

  def delete(path)
    request(Net::HTTP::Delete, path, nil)
  end

  private

  def request(verb, path, body)
    handle(perform(build_request(verb, path, body)))
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def build_request(verb, path, body)
    request = verb.new(path)
    request['api-key'] = @api_key if @api_key

    unless body.nil?
      request['content-type'] = 'application/json'
      request.body = JSON.generate(body)
    end

    request
  end

  def perform(request)
    return @client.request(request) if @client

    Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                          open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
      http.request(request)
    end
  end

  def handle(response)
    status = response.code.to_i
    payload = parse(response.body)

    return { ok: false, status: status, error: payload } unless (200..299).cover?(status)

    { ok: true }.merge(payload.is_a?(Hash) ? payload : {})
  end

  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body, symbolize_names: true)
  rescue JSON::ParserError
    { ok: false, error: 'resposta do Qdrant não é JSON válido' }
  end
end
