# frozen_string_literal: true

# Dublê do cliente HTTP: registra as requisições montadas pelo transporte e
# devolve uma resposta preparada, sem abrir conexão.
class FakeHttpClient
  Response = Struct.new(:code, :body)

  attr_reader :requests

  def initialize(code: '200', body: '{"result":{"status":"ok"}}')
    @code = code
    @body = body
    @requests = []
  end

  def request(net_request)
    @requests << net_request
    Response.new(@code, @body)
  end
end
