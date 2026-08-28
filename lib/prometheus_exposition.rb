# frozen_string_literal: true

# Escreve métricas no formato de exposição de texto do Prometheus.
#
# Está separado do `MetricRegistry` porque são duas responsabilidades que mudam
# por motivos diferentes: o registro é sobre **acumular** — declarar, somar,
# proteger contra rótulo errado — e isto aqui é sobre **escrever** num formato
# que pertence ao Prometheus. Com os dois separados, trocar o formato (por
# OpenMetrics, digamos) não encosta na contabilidade.
#
# Duas regras do formato que o código respeita e é fácil errar:
#
# - **Os buckets do histograma são cumulativos.** Cada um conta tudo que caiu
#   abaixo dele, e o `+Inf` conta tudo — por isso ele é o próprio total de
#   observações.
# - **Aspas e barras invertidas em rótulo têm de ser escapadas.** Um valor com
#   aspas partiria a linha no meio e o scrape inteiro seria descartado.
module PrometheusExposition
  CONTENT_TYPE = 'text/plain; version=0.0.4; charset=utf-8'
  ESCAPES = { '\\' => '\\\\', '"' => '\"', "\n" => '\n' }.freeze

  # Saída ordenada por nome, sempre: dois scrapes seguidos precisam ser
  # comparáveis com `diff`, e a ordem de inserção de um Hash não é contrato.
  def self.render(metrics, values)
    metrics.keys.sort.map { |name| metric(name, metrics[name], values[name] || {}) }.join
  end

  def self.metric(name, definition, values)
    "# HELP #{name} #{escape(definition[:help])}\n# TYPE #{name} #{definition[:type]}\n" +
      samples(name, definition, values).join
  end

  def self.samples(name, definition, values)
    return ["#{name} #{number(definition[:sample].call)}\n"] if definition[:sample]
    return histogram(name, definition[:buckets], values) if definition[:type] == :histogram
    # Métrica sem rótulo nasce em zero, para que o painel diga "zero" em vez de
    # "sem dados" antes da primeira requisição. Com rótulo isso é impossível: a
    # série só existe depois da primeira amostra, e inventá-la seria inventar um
    # valor.
    return ["#{name} 0\n"] if values.empty? && definition[:labels].empty?

    sorted(values).map { |labels, value| "#{name}#{render_labels(labels)} #{number(value)}\n" }
  end

  def self.histogram(name, buckets, values)
    sorted(values).flat_map { |labels, data| series(name, buckets, labels, data) }
  end

  def self.series(name, buckets, labels, data)
    buckets.map { |bucket| bucket_line(name, labels, number(bucket), data[:buckets][bucket]) } +
      [bucket_line(name, labels, '+Inf', data[:count]),
       "#{name}_sum#{render_labels(labels)} #{number(data[:sum])}\n",
       "#{name}_count#{render_labels(labels)} #{data[:count]}\n"]
  end

  def self.bucket_line(name, labels, limit, count)
    "#{name}_bucket#{render_labels(labels.merge(le: limit))} #{count}\n"
  end

  def self.sorted(values)
    values.sort_by { |labels, _| labels.values.map(&:to_s) }
  end

  def self.render_labels(labels)
    return '' if labels.empty?

    "{#{labels.map { |label, value| "#{label}=\"#{escape(value)}\"" }.join(',')}}"
  end

  # A forma com bloco é de propósito: no `gsub` com string de substituição a
  # barra invertida ainda tem significado, e escapar barra com barra escapada
  # vira um trava-língua que ninguém revisa direito.
  def self.escape(value)
    value.to_s.gsub(/[\\"\n]/) { |char| ESCAPES.fetch(char) }
  end

  # Inteiro sai sem casa decimal: contador escrito como "3" e não "3.0" é o que
  # se espera ver ao dar um curl no /metrics.
  def self.number(value)
    return value.to_s unless value.is_a?(Float)

    value == value.to_i ? value.to_i.to_s : value.to_s
  end
end
