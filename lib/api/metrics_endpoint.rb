# frozen_string_literal: true

require_relative '../prometheus_exposition'

module Api
  # Expõe o registro de métricas em `GET /metrics`, no formato que o Prometheus
  # lê.
  #
  # É um middleware e não uma rota da App de propósito: a App trata de
  # documentos, busca e pergunta, e não tem por que conhecer o registro de
  # métricas. Aqui ele entra por injeção e sai por uma única rota.
  #
  # Fica **dentro** da autenticação: `/metrics` conta rota, latência e status,
  # que juntos são o mapa de como a aplicação é usada. O escopo é próprio, e não
  # `read`, porque quem lê documentos não precisa ver a operação — e o Prometheus
  # não precisa ler documento nenhum para raspar métrica. Menor privilégio nas
  # duas direções.
  class MetricsEndpoint
    PATH = '/metrics'

    def initialize(app, registry:)
      @app = app
      @registry = registry
    end

    def call(env)
      return @app.call(env) unless metrics?(env)

      [200, { 'content-type' => PrometheusExposition::CONTENT_TYPE }, [@registry.render]]
    end

    private

    def metrics?(env)
      env['REQUEST_METHOD'] == 'GET' && env['PATH_INFO'] == PATH
    end
  end
end
