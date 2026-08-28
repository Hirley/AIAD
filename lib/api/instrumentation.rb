# frozen_string_literal: true

require_relative '../metric_registry'
require_relative 'access_policy'

module Api
  # Middleware que conta e cronometra as requisições HTTP.
  #
  # Quatro decisões definem o comportamento:
  #
  # - **A rota do rótulo é normalizada, o caminho cru nunca entra.** Um
  #   varredor de vulnerabilidade pedindo mil caminhos inventados criaria mil
  #   séries temporais permanentes; com a normalização ele cria uma, chamada
  #   `outra`. Cardinalidade de rótulo é a forma mais comum de derrubar um
  #   Prometheus, e vem de fora.
  # - **A lista de rotas conhecidas sai da AccessPolicy.** Uma rota nova já
  #   aparece rotulada sem ninguém lembrar de mexer aqui, e não há duas listas
  #   para divergirem.
  # - **Histograma, não média.** A média de latência é a estatística que mais
  #   esconde: dez respostas de 1 s e uma de 30 s dão uma média tranquila. Com
  #   buckets, o p95 e o p99 se calculam na hora da consulta, e a escolha do
  #   percentil fica com quem olha o painel.
  # - **Fica por fora da autenticação, de propósito.** Um pico de 401 é
  #   exatamente o que se quer ver no gráfico: pode ser chave rotacionada sem
  #   avisar ou alguém tentando adivinhar credencial.
  class Instrumentation
    REQUESTS = 'aiad_http_requests_total'
    DURATION = 'aiad_http_request_duration_seconds'
    IN_FLIGHT = 'aiad_http_requests_in_flight'
    EXCEPTIONS = 'aiad_http_exceptions_total'
    OTHER_ROUTE = 'outra'
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    KNOWN_ROUTES = AccessPolicy::RULES.keys.map(&:last).uniq.freeze

    # Pública porque o log estruturado usa a mesma normalização: rótulo de
    # métrica e campo de log que discordam sobre o nome da rota fazem os dois
    # painéis pararem de se cruzar.
    def self.route_for(path)
      KNOWN_ROUTES.include?(path.to_s) ? path.to_s : OTHER_ROUTE
    end

    def self.install(registry)
      registry.counter(REQUESTS, help: 'Requisições HTTP atendidas.', labels: %i[method route status])
      registry.histogram(DURATION, help: 'Duração das requisições HTTP, em segundos.', labels: %i[method route])
      registry.gauge(IN_FLIGHT, help: 'Requisições HTTP em andamento.')
      registry.counter(EXCEPTIONS, help: 'Requisições que terminaram em exceção não tratada.', labels: %i[route])

      registry
    end

    def initialize(app, registry:, clock: MONOTONIC)
      @app = app
      @registry = registry
      @clock = clock
    end

    def call(env)
      route = self.class.route_for(env['PATH_INFO'])
      method = env['REQUEST_METHOD'].to_s
      started = @clock.call
      @registry.increment(IN_FLIGHT)

      record(method, route, started) { @app.call(env) }
    ensure
      @registry.increment(IN_FLIGHT, by: -1)
    end

    private

    # A duração é medida no `ensure` porque requisição lenta que estourou é
    # justamente a que se quer ver no gráfico. Já o contador de status só conta
    # quando há status: exceção vira um contador próprio, em vez de virar um
    # `500` que ninguém devolveu.
    def record(method, route, started)
      response = yield
      @registry.increment(REQUESTS, labels: { method: method, route: route, status: response[0].to_s })

      response
    rescue StandardError
      @registry.increment(EXCEPTIONS, labels: { route: route })
      raise
    ensure
      @registry.observe(DURATION, @clock.call - started, labels: { method: method, route: route })
    end
  end
end
