# frozen_string_literal: true

require_relative 'prometheus_exposition'

# Registro de métricas no formato de exposição do Prometheus.
#
# Escrito à mão, sem gem: o formato de texto do Prometheus é pequeno e estável,
# e uma dependência nova na imagem de produção custa mais do que estas linhas.
# O resto do projeto segue a mesma linha — BM25, RRF e o tokenizador também são
# à mão, porque entender o mecanismo é metade do ponto.
#
# Cinco decisões definem o comportamento:
#
# - **Métrica se declara antes de usar.** Incrementar um nome não declarado
#   levanta erro em vez de criar a série na hora. Um erro de digitação viraria
#   uma segunda série que ninguém olha, e o painel ficaria vazio sem avisar.
# - **Os rótulos também se declaram.** Mesmo motivo, um nível abaixo: rótulo
#   digitado errado cria uma série irmã em silêncio.
# - **Rótulo é de cardinalidade baixa, sempre.** Método, rota e status — nunca
#   id de usuário, pergunta ou caminho cru. Cada combinação de rótulos é uma
#   série temporal guardada para sempre; rótulo livre derruba o Prometheus, e
#   não o serviço que ele deveria observar.
# - **Métrica amostrada é lida no scrape.** Memória residente e CPU não se
#   acumulam num contador nosso: o valor certo é o que o sistema diz no momento
#   da coleta. Declarar com bloco deixa a diferença explícita.
# - **Escrever o formato é de outro.** Isto aqui acumula; quem escreve o texto
#   é a `PrometheusExposition`. São duas coisas que mudam por motivos
#   diferentes.
class MetricRegistry
  class UnknownMetricError < StandardError; end
  class DuplicateMetricError < StandardError; end
  class WrongTypeError < StandardError; end
  class UnknownLabelError < StandardError; end

  # Buckets em segundos, cobrindo de resposta local a chamada de modelo lenta.
  # São cumulativos por definição do Prometheus: cada um conta tudo que caiu
  # abaixo dele.
  DEFAULT_BUCKETS = [0.005, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10].freeze

  def initialize
    @metrics = {}
    @values = Hash.new { |hash, name| hash[name] = {} }
    @mutex = Mutex.new
  end

  def counter(name, help:, labels: [], &sample)
    declare(name, :counter, help, labels, sample)
  end

  def gauge(name, help:, labels: [], &sample)
    declare(name, :gauge, help, labels, sample)
  end

  def histogram(name, help:, labels: [], buckets: DEFAULT_BUCKETS)
    declare(name, :histogram, help, labels, nil, buckets: buckets.sort)
  end

  def increment(name, labels: {}, by: 1)
    change(name, %i[counter gauge], labels) { |current| current.to_f + by }
  end

  def set(name, value, labels: {})
    change(name, [:gauge], labels) { value.to_f }
  end

  def observe(name, value, labels: {})
    change(name, [:histogram], labels) do |current|
      current ||= { buckets: Hash.new(0), sum: 0.0, count: 0 }
      accumulate(current, metric!(name)[:buckets], value.to_f)
    end
  end

  # O snapshot sai debaixo do mutex e a renderização acontece fora dele: assim
  # os blocos de amostragem não rodam com o lock tomado, e um bloco que demore
  # não segura as threads que estão atendendo requisição.
  def render
    snapshot = @mutex.synchronize { @values.transform_values(&:dup) }

    PrometheusExposition.render(@metrics, snapshot)
  end

  private

  def declare(name, type, help, labels, sample, buckets: nil)
    raise DuplicateMetricError, "métrica já declarada: #{name}" if @metrics.key?(name)
    raise ArgumentError, "métrica amostrada não aceita rótulos: #{name}" if sample && labels.any?

    @metrics[name] = { type: type, help: help, labels: labels.map(&:to_sym).sort, sample: sample,
                       buckets: buckets }
  end

  def change(name, allowed, labels)
    metric = metric!(name)
    unless allowed.include?(metric[:type])
      raise WrongTypeError,
            "#{name} é #{metric[:type]}, não #{allowed.join(' nem ')}"
    end

    key = validated_labels(name, metric, labels)
    @mutex.synchronize { @values[name][key] = yield(@values[name][key]) }
  end

  def metric!(name)
    @metrics.fetch(name) { raise UnknownMetricError, "métrica não declarada: #{name}" }
  end

  def validated_labels(name, metric, labels)
    given = labels.keys.map(&:to_sym).sort
    unless given == metric[:labels]
      raise UnknownLabelError,
            "#{name} espera os rótulos #{metric[:labels].join(', ')} (recebido: #{given.join(', ')})"
    end

    given.to_h { |label| [label, labels[label] || labels[label.to_s]] }
  end

  def accumulate(current, buckets, value)
    buckets.each { |bucket| current[:buckets][bucket] += 1 if value <= bucket }
    { buckets: current[:buckets], sum: current[:sum] + value, count: current[:count] + 1 }
  end
end
