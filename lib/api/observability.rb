# frozen_string_literal: true

require_relative '../composite_exporter'
require_relative '../langfuse_exporter'
require_relative '../metric_registry'
require_relative '../process_collector'
require_relative '../prometheus_evaluation_log'
require_relative '../prometheus_trace_exporter'
require_relative '../tracer'
require_relative 'instrumentation'
require_relative 'request_logger'

module Api
  # A instrumentação que envolve a aplicação, separada de quem a monta.
  #
  # Está fora do `Build` porque é outro assunto: lá se responde "o que a API
  # faz", aqui "como se observa o que ela faz". Os dois cresceram juntos até
  # ficar difícil achar qualquer um dos dois no meio do outro.
  module Observability
    # O registro nasce com as métricas já declaradas: métrica que só aparece
    # depois da primeira requisição faz o painel dizer "sem dados" onde a
    # verdade é "zero", e essas duas coisas se investigam de formas bem
    # diferentes.
    def self.registry
      MetricRegistry.new.tap do |registry|
        Instrumentation.install(registry)
        ProcessCollector.new.install(registry)
        PrometheusTraceExporter.install(registry)
        PrometheusEvaluationLog.install(registry)
      end
    end

    # O trace vai para os dois lugares que respondem perguntas diferentes: o
    # Prometheus agrega e diz que o custo subiu ontem às 3h; o Langfuse guarda
    # a requisição inteira e diz por quê — qual pergunta, qual resposta, qual
    # span demorou. Sem chave do Langfuse sobra só o Prometheus, e a aplicação
    # sobe igual: observabilidade externa é opcional, não requisito de boot.
    def self.tracer(registry:, env: ENV)
      Tracer.new(exporter: CompositeExporter.for(PrometheusTraceExporter.new(registry: registry),
                                                 LangfuseExporter.from_env(env)))
    end

    # A ordem da pilha não é acidental. Log e métrica ficam **por fora** da
    # autenticação, para que 401 e 403 apareçam no gráfico e no log: um pico de
    # 401 é chave rotacionada sem avisar ou alguém tentando adivinhar
    # credencial, e não dá para ver isso se a requisição morre antes de ser
    # contada. Já o `/metrics` fica **por dentro**, montado no `Build`, porque
    # é uma rota como qualquer outra e passa pelo mesmo controle de acesso.
    def self.wrap(app, registry:, logs:)
      RequestLogger.new(Instrumentation.new(app, registry: registry), io: logs,
                                                                      route: Instrumentation.method(:route_for))
    end
  end
end
