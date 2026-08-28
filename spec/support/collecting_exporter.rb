# frozen_string_literal: true

# Exportador de trace que só guarda o que recebeu, para os exemplos olharem a
# árvore pronta. É o mesmo papel que o transporte falso do Qdrant cumpre: o
# seam onde o mundo externo começa.
class CollectingExporter
  attr_reader :traces

  def initialize(&failure)
    @traces = []
    @failure = failure
  end

  def export(trace)
    @failure&.call
    @traces << trace
  end

  def last
    @traces.last
  end
end
