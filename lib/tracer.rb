# frozen_string_literal: true

require 'securerandom'

# Tracing de chamadas de LLM, agentes e cadeias de RAG: cada pedaço de trabalho
# vira um span com duração, entrada, saída e o que deu errado, aninhados na
# forma em que aconteceram.
#
# Cinco decisões que definem o comportamento:
#
# - **O valor de retorno não muda.** `trace` devolve o que o bloco devolveu.
#   Tracer que mexe no retorno obriga a reescrever o código em volta, e aí não
#   se instrumenta nada.
# - **Relógio monotônico.** Hora de parede dá salto (NTP, horário de verão) e
#   produz duração negativa. Aqui o que importa é intervalo, não data.
# - **Erro é registrado e re-levantado.** Observabilidade que engole falha
#   troca um problema por dois.
# - **A exportação acontece só quando a raiz fecha.** Trace parcial não explica
#   nada, e exportar span a span multiplicaria as chamadas de rede.
# - **Exportador quebrado não derruba a aplicação.** Se o coletor estiver fora
#   do ar, o trace se perde; a requisição do usuário, não. É a inversão certa:
#   ninguém aceita cair porque o observador caiu.
class Tracer
  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
  RANDOM_ID = -> { SecureRandom.hex(8) }

  # Tracer desligado: cumpre a mesma interface e não guarda nada. Existe para
  # instrumentação nascer desligada por padrão — quem não quer observabilidade
  # paga uma chamada de método e nada mais, sem `if @tracer` espalhado pelo
  # código instrumentado.
  module Null
    # Span que aceita tudo e ignora tudo, para o código instrumentado poder
    # anotar saída, uso e metadados sem saber se alguém está ouvindo.
    module Span
      def self.span(_name, **_options) = yield(self)
      def self.output=(_value); end
      def self.usage=(_value); end
      def self.annotate(_fields); end
    end

    def self.trace(_name, **_options) = yield(Span)
  end

  def self.null = Null

  def initialize(exporter: nil, clock: MONOTONIC, ids: RANDOM_ID)
    @exporter = exporter
    @clock = clock
    @ids = ids
  end

  # A exportação vai num `ensure`: trace de requisição que falhou é justamente
  # o que se vai olhar depois, então não pode ser o único que se perde.
  def trace(name, input: nil, metadata: {}, &block)
    span = Span.new(name: name, input: input, metadata: metadata, id: @ids.call, clock: @clock, ids: @ids)

    span.run(&block)
  ensure
    export(span.to_h) if span
  end

  private

  def export(trace)
    @exporter&.export(trace)
  rescue StandardError
    nil
  end

  # Um span do trace. Recebe o relógio e o gerador de id de fora pelo mesmo
  # motivo de sempre neste projeto: para o teste conseguir olhar duração e id
  # sem depender de tempo real nem de sorte.
  class Span
    attr_accessor :output, :usage
    attr_reader :metadata

    def initialize(name:, id:, clock:, ids:, input: nil, metadata: {})
      @name = name
      @id = id
      @clock = clock
      @ids = ids
      @input = input
      @metadata = metadata
      @spans = []
      @status = :ok
    end

    def span(name, input: nil, metadata: {}, &block)
      child = self.class.new(name: name, input: input, metadata: metadata, id: @ids.call, clock: @clock, ids: @ids)
      @spans << child

      child.run(&block)
    end

    def annotate(fields)
      @metadata = @metadata.merge(fields)
    end

    # A saída padrão é o que o bloco devolveu: escrever `span.output =` em todo
    # span instrumentado seria ruído, porque é isso na esmagadora maioria dos
    # casos. Definir explicitamente continua ganhando.
    def run
      started = @clock.call
      result = yield(self)
      @output = result if @output.nil?

      result
    rescue StandardError => e
      fail!(e)
      raise
    ensure
      @duration = @clock.call - started
    end

    def to_h
      { id: @id, name: @name, input: @input, output: @output, metadata: @metadata, usage: @usage,
        status: @status, error: @error, duration: @duration, spans: @spans.map(&:to_h) }
    end

    protected

    # O erro sobe pela pilha de spans: quem olha a raiz precisa ver que aquela
    # requisição falhou, sem ter de varrer a árvore inteira atrás do span roxo.
    def fail!(error)
      @status = :error
      @error = "#{error.class}: #{error.message}"
    end
  end
end
