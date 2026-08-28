# frozen_string_literal: true

require 'json'
require 'time'
require 'securerandom'

module Api
  # Log estruturado: uma linha JSON por requisição.
  #
  # Cinco decisões definem o comportamento:
  #
  # - **Uma linha, um evento, JSON.** É o que Loki, `jq` e qualquer coletor
  #   leem sem regex. Log em prosa obriga a escrever um parser por formato de
  #   mensagem, e o parser quebra na primeira vez que alguém melhora o texto.
  # - **Nunca o corpo, nunca a chave.** O corpo de `/documents` é um documento
  #   inteiro e o de `/ask` é a pergunta do usuário; nenhum dos dois tem por que
  #   ficar em disco de log. Da credencial vai só o **nome** do principal, que
  #   é o que responde "quem fez isso".
  # - **O id de requisição vindo do cliente é dado, não confiança.** Entra
  #   sanitizado e truncado: uma quebra de linha nesse header viraria uma
  #   segunda linha de log inteiramente forjada, e log forjado é pior que log
  #   ausente.
  # - **`path` cru e `route` normalizada, os dois.** O cru serve para
  #   investigar um caso; o normalizado serve para agrupar e casa com o rótulo
  #   da métrica. Em log a cardinalidade não custa o que custa no Prometheus.
  # - **Exceção é registrada e re-levantada.** Mesma inversão do exportador de
  #   trace: quem observa não decide o destino de quem faz.
  class RequestLogger
    MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    NOW = -> { Time.now.utc }
    RANDOM_ID = -> { SecureRandom.hex(8) }
    REQUEST_ID_HEADER = 'HTTP_X_REQUEST_ID'
    RESPONSE_HEADER = 'x-request-id'
    UNSAFE_ID = /[^A-Za-z0-9._-]/
    MAX_ID_LENGTH = 64
    MILLISECONDS = 1000

    def initialize(app, io: $stdout, clock: MONOTONIC, now: NOW, ids: RANDOM_ID, route: nil)
      @app = app
      @io = io
      @clock = clock
      @now = now
      @ids = ids
      @route = route || ->(path) { path }
      # Sem isto a saída padrão de um container (que não é terminal) sai
      # bufferizada em blocos, e o log do incidente aparece minutos depois do
      # incidente — ou nunca, se o processo morrer antes de esvaziar o buffer.
      @io.sync = true if @io.respond_to?(:sync=)
    end

    def call(env)
      request_id = request_id_for(env)
      started = @clock.call

      status, headers, body = @app.call(env)
      headers = headers.merge(RESPONSE_HEADER => request_id)
      write(entry(env, request_id, started).merge(level: 'info', status: status))

      [status, headers, body]
    rescue StandardError => e
      write(entry(env, request_id, started).merge(level: 'error', status: 500, error: e.class.name))
      raise
    end

    private

    # O principal é lido **depois** da chamada: quem o coloca no env é o
    # middleware de autenticação, que roda por dentro deste. Antes da chamada
    # ainda não há quem.
    def entry(env, request_id, started)
      {
        ts: @now.call.iso8601,
        request_id: request_id,
        method: env['REQUEST_METHOD'],
        path: env['PATH_INFO'],
        route: @route.call(env['PATH_INFO']),
        duration_ms: ((@clock.call - started) * MILLISECONDS).round(2),
        principal: env['aiad.principal']&.fetch(:name, nil)
      }
    end

    def request_id_for(env)
      given = env[REQUEST_ID_HEADER].to_s.gsub(UNSAFE_ID, '')[0, MAX_ID_LENGTH].to_s

      given.empty? ? @ids.call : given
    end

    def write(fields)
      @io.write("#{JSON.generate(fields)}\n")
    end
  end
end
