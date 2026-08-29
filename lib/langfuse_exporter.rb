# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

require_relative 'langfuse_batch'

# Exportador de trace para o Langfuse: manda a árvore inteira de spans — com
# pergunta, resposta, tokens e o que falhou — para a rota de ingestão.
#
# É irmão do `PrometheusTraceExporter` e os dois recebem o mesmo trace. A
# divisão de trabalho é a de sempre: o Prometheus guarda série temporal
# agregada e responde "o custo subiu ontem às 3h"; o Langfuse guarda a
# requisição individual e responde "por quê" — qual prompt, qual resposta, qual
# span demorou. Uma pergunta não se responde com a ferramenta da outra.
#
# A forma do payload não mora aqui, e sim no `LangfuseBatch`. A separação é
# proposital: **este arquivo é o que já se sabe certo** — autenticação,
# timeout, tratamento de erro — e o `LangfuseBatch` é a parte que nunca foi
# confirmada contra um servidor real. Vale ler o comentário de lá antes de
# apontar isto para uma conta de verdade.
#
# Três decisões definem o comportamento:
#
# - **O transporte é injetável**, como no `AnthropicLlm`. É o que permite
#   testar a montagem do pedido, a autenticação e o tratamento de erro sem rede
#   e sem credencial, e é por isso que a suíte inteira continua rodando
#   offline.
# - **As chaves vêm do ambiente e nunca do código**, e não aparecem em
#   `inspect`. Mesma proteção do `ApiKeyStore`: um dump de exceção não pode
#   carregar credencial.
# - **Falha vira exceção nossa e o `Tracer` a engole.** Aqui se levanta
#   `Error`; quem chama em produção é o `Tracer`, que já decidiu não derrubar a
#   requisição do usuário por causa do observador. Engolir aqui também
#   deixaria um teste de integração passar com o Langfuse fora do ar — e uma
#   chave errada nunca daria sinal nenhum.
class LangfuseExporter
  class Error < StandardError; end

  DEFAULT_URL = 'https://cloud.langfuse.com'
  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 10
  PATH = '/api/public/ingestion'

  attr_reader :url

  def initialize(public_key:, secret_key:, url: DEFAULT_URL, open_timeout: DEFAULT_OPEN_TIMEOUT,
                 read_timeout: DEFAULT_READ_TIMEOUT, client: nil, ids: LangfuseBatch::RANDOM_ID)
    @public_key = public_key
    @secret_key = secret_key
    @url = url
    @uri = URI.parse(url)
    @open_timeout = open_timeout
    @read_timeout = read_timeout
    @client = client
    @batch = LangfuseBatch.new(ids: ids)
  end

  # Sem o par de chaves, `nil`: quem monta a aplicação decide o que fazer com a
  # ausência. Um exportador pela metade só falharia na primeira requisição,
  # longe da causa — e falharia dentro do `rescue` do `Tracer`, que é o pior
  # lugar para um erro de configuração se esconder.
  def self.from_env(env = ENV)
    public_key = setting(env, 'LANGFUSE_PUBLIC_KEY')
    secret_key = setting(env, 'LANGFUSE_SECRET_KEY')
    return nil if public_key.nil? || secret_key.nil?

    new(public_key: public_key, secret_key: secret_key, url: setting(env, 'LANGFUSE_URL') || DEFAULT_URL)
  end

  # Variável em branco conta como ausente: um `LANGFUSE_SECRET_KEY=` esquecido
  # no .env não pode virar uma tentativa de autenticar com string vazia.
  def self.setting(env, name)
    value = env[name].to_s.strip

    value.empty? ? nil : value
  end
  private_class_method :setting

  def export(trace)
    response = perform(request_for(@batch.events_for(trace)))
    status = response.code.to_i

    raise Error, failure_message(status, response.body) unless (200..299).cover?(status)

    nil
  rescue Timeout::Error, IOError, SystemCallError => e
    raise Error, "falha de rede ao mandar o trace: #{e.class}"
  end

  def inspect
    "#<#{self.class.name} url=#{@url.inspect}>"
  end

  private

  def request_for(events)
    request = Net::HTTP::Post.new(PATH)
    request.basic_auth(@public_key, @secret_key)
    request['content-type'] = 'application/json'
    request.body = JSON.generate(batch: events)

    request
  end

  def perform(request)
    return @client.request(request) if @client

    Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                          open_timeout: @open_timeout, read_timeout: @read_timeout) do |http|
      http.request(request)
    end
  end

  # A mensagem do servidor entra porque é ela que diz o que corrigir — chave
  # errada e formato errado respondem coisas bem diferentes. O corpo inteiro,
  # não: pode trazer de volta o prompt que acabou de subir.
  def failure_message(status, body)
    detail = parse(body)[:message]

    "Langfuse respondeu #{status}#{": #{detail}" if detail}"
  end

  def parse(body)
    return {} if body.nil? || body.empty?

    JSON.parse(body, symbolize_names: true)
  rescue JSON::ParserError
    {}
  end
end
