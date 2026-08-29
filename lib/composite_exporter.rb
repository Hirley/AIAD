# frozen_string_literal: true

# Manda o mesmo trace para vários exportadores.
#
# Existe porque o trace tem dois destinos com propósitos diferentes: o
# `PrometheusTraceExporter`, que agrega em série temporal e responde "o custo
# subiu ontem às 3h", e o `LangfuseExporter`, que guarda a requisição inteira e
# responde "por quê". O `Tracer` recebe um exportador só, e é aqui que os dois
# viram um.
#
# Duas decisões definem o comportamento:
#
# - **A falha de um não impede os outros.** O Langfuse é serviço externo e cai;
#   o registro de métricas é memória do processo e não cai. Se a queda do
#   primeiro cortasse a entrega ao segundo, um serviço fora do ar levaria junto
#   a métrica que se usa justamente para perceber que algo está fora do ar — e
#   a ordem da lista, que ninguém pensa a respeito, decidiria o que sobrevive.
# - **A falha não some.** Depois de todos serem servidos, o primeiro erro
#   sobe. Quem chama em produção é o `Tracer`, que já decidiu não derrubar a
#   requisição por causa do observador; engolir aqui também deixaria uma chave
#   errada passar despercebida para sempre.
class CompositeExporter
  # Envolver um exportador só seria uma camada que não decide nada e apareceria
  # em todo backtrace daqui para frente. `nil` some: sem chave do Langfuse,
  # sobra o Prometheus, e esse é o caso normal.
  def self.for(*exporters)
    configured = exporters.compact

    configured.size > 1 ? new(configured) : configured.first
  end

  def initialize(exporters)
    @exporters = exporters
  end

  def export(trace)
    failure = @exporters.filter_map { |exporter| deliver(exporter, trace) }.first

    raise failure if failure
  end

  private

  def deliver(exporter, trace)
    exporter.export(trace)
    nil
  rescue StandardError => e
    e
  end
end
