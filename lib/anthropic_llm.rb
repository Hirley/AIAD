# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

# Modelo de verdade, pela API de mensagens da Anthropic. Cumpre a mesma
# interface mínima que o resto do projeto sempre exigiu de um modelo:
# `complete(prompt)` devolvendo texto.
#
# Cinco decisões definem o comportamento:
#
# - **O transporte é injetável**, como no `HttpQdrantTransport`. É isso que
#   permite testar a montagem do pedido, o tratamento de erro e a leitura da
#   resposta sem rede e sem credencial — e é por isso que a suíte inteira
#   continua rodando offline.
# - **A chave vem do ambiente e nunca do código.** `from_env` devolve `nil`
#   quando não há chave configurada, e quem chama decide o que fazer com a
#   ausência. Sem chave não há objeto pela metade.
# - **A chave não aparece em `inspect`.** Mesma proteção do `ApiKeyStore`: um
#   dump de exceção não pode carregar credencial.
# - **Erro do provedor vira exceção nossa**, com a mensagem do provedor mas sem
#   o corpo inteiro. Quem chama trata `Error`, não `Net::HTTPResponse`.
# - **Timeout é curto e explícito.** Chamada de modelo sem timeout é a forma
#   mais fácil de travar um processo web inteiro: as cinco threads do Puma
#   ficariam presas esperando um servidor que não responde.
class AnthropicLlm
  class Error < StandardError; end

  DEFAULT_URL = 'https://api.anthropic.com'
  DEFAULT_MODEL = 'claude-sonnet-5'
  DEFAULT_MAX_TOKENS = 1024
  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 60
  API_VERSION = '2023-06-01'
  PATH = '/v1/messages'

  attr_reader :model

  def initialize(api_key:, model: DEFAULT_MODEL, url: DEFAULT_URL, max_tokens: DEFAULT_MAX_TOKENS,
                 open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT, client: nil)
    @api_key = api_key
    @model = model
    @uri = URI.parse(url)
    @max_tokens = max_tokens
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @client = client
  end

  # Sem chave, `nil`: a aplicação decide se cai no modelo extrativo ou se
  # recusa a rota que exige modelo. Devolver um objeto que falha na primeira
  # chamada empurraria o erro para longe da causa.
  def self.from_env(env = ENV)
    key = setting(env, 'ANTHROPIC_API_KEY')
    return nil if key.nil?

    new(api_key: key, model: setting(env, 'AIAD_MODEL') || DEFAULT_MODEL,
        url: setting(env, 'ANTHROPIC_URL') || DEFAULT_URL)
  end

  # Variável em branco conta como ausente: um `AIAD_MODEL=` esquecido no .env
  # não pode virar um nome de modelo vazio mandado para o provedor.
  def self.setting(env, name)
    value = env[name].to_s.strip

    value.empty? ? nil : value
  end
  private_class_method :setting

  def complete(prompt)
    response = perform(request_for(prompt))
    status = response.code.to_i
    payload = parse(response.body)

    raise Error, failure_message(status, payload) unless (200..299).cover?(status)

    text_from(payload)
  rescue Timeout::Error, IOError, SystemCallError => e
    raise Error, "falha de rede ao chamar o modelo: #{e.class}"
  end

  def inspect
    "#<#{self.class.name} model=#{@model.inspect}>"
  end

  private

  def request_for(prompt)
    request = Net::HTTP::Post.new(PATH)
    request['x-api-key'] = @api_key
    request['anthropic-version'] = API_VERSION
    request['content-type'] = 'application/json'
    request.body = JSON.generate(model: @model, max_tokens: @max_tokens,
                                 messages: [{ role: 'user', content: prompt.to_s }])

    request
  end

  def perform(request)
    return @client.request(request) if @client

    Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                          open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
      http.request(request)
    end
  end

  # A resposta vem como uma lista de blocos; só os de texto interessam, e eles
  # se juntam na ordem em que vieram.
  def text_from(payload)
    blocks = payload[:content]
    raise Error, 'resposta do modelo sem conteúdo' unless blocks.is_a?(Array)

    blocks.select { |block| block[:type] == 'text' }.map { |block| block[:text].to_s }.join
  end

  def failure_message(status, payload)
    detail = payload.dig(:error, :message) || payload[:error]

    "modelo respondeu #{status}#{": #{detail}" if detail}"
  end

  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end
end
