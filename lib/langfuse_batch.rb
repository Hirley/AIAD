# frozen_string_literal: true

require 'securerandom'
require 'time'

# Traduz um trace do `Tracer` para o lote de eventos que a rota de ingestão do
# Langfuse recebe.
#
# **Este arquivo é a única parte do projeto cujo formato não foi verificado
# contra o serviço real.** É o meu melhor entendimento da API de ingestão do
# Langfuse, escrito sem uma instância para confirmar. O Qdrant roda em
# container aqui e a API da Anthropic é exercitada de verdade quando há chave;
# o Langfuse, não. Nomes de campo (`traceId`, `parentObservationId`,
# `startTime`, `usage`), os tipos de evento e a forma do lote podem estar
# errados.
#
# Está separado do `LangfuseExporter` por causa disso: lá está o que já se sabe
# certo — autenticação, timeout, tratamento de erro, tudo exercitado por teste.
# Aqui está o que falta confirmar. Quando alguém apontar isto para uma conta de
# verdade e o formato estiver errado, o conserto é neste arquivo e a suíte que
# o cobre diz exatamente o que mudou de forma.
#
# Três decisões definem a tradução:
#
# - **O trace é o contêiner, não uma observação.** A raiz vira as duas coisas:
#   abre o trace e também aparece como observação. Sem a segunda, a duração da
#   raiz não existiria em lugar nenhum e a cascata começaria no primeiro filho,
#   como se o trabalho de fora fosse instantâneo.
# - **Span com `usage` é geração; o resto é span.** É essa distinção que faz
#   token e custo aparecerem no painel. O critério é ter `usage`, o mesmo do
#   `PrometheusTraceExporter` — duas definições de "isto foi uma chamada de
#   modelo" divergiriam na primeira mudança, e aí os dois painéis contariam
#   números diferentes para o mesmo dia.
# - **A hora vem do carimbo de parede; a duração, do monotônico.** O `Tracer`
#   mede intervalo com relógio que não anda para trás e carimba o início com
#   hora de parede uma vez só. O fim se calcula somando os dois. Ler o relógio
#   de parede de novo no fim reintroduziria o salto de NTP que o monotônico
#   existe para evitar.
class LangfuseBatch
  RANDOM_ID = -> { SecureRandom.uuid }
  ERROR_LEVEL = 'ERROR'
  TOKEN_UNIT = 'TOKENS'

  def initialize(ids: RANDOM_ID)
    @ids = ids
  end

  # A raiz abre o trace e as observações descem em pré-ordem, para o lote
  # chegar na mesma ordem em que o trabalho aconteceu.
  def events_for(trace)
    [trace_event(trace)] + observations(trace, trace[:id], nil)
  end

  private

  def observations(span, trace_id, parent_id)
    [observation_event(span, trace_id, parent_id)] +
      (span[:spans] || []).flat_map { |nested| observations(nested, trace_id, span[:id]) }
  end

  def trace_event(trace)
    event('trace-create', trace[:started_at],
          { id: trace[:id], name: trace[:name], input: trace[:input], output: trace[:output],
            metadata: trace[:metadata], timestamp: iso(trace[:started_at]) })
  end

  def observation_event(span, trace_id, parent_id)
    generation = generation?(span)

    event(generation ? 'generation-create' : 'span-create', span[:started_at],
          { id: span[:id], traceId: trace_id, parentObservationId: parent_id, name: span[:name],
            startTime: iso(span[:started_at]), endTime: iso(ended_at(span)), input: span[:input],
            output: span[:output], metadata: span[:metadata], level: level_of(span),
            statusMessage: span[:error] }.merge(generation ? billing(span) : {}))
  end

  def event(type, timestamp, body)
    { id: @ids.call, type: type, timestamp: iso(timestamp), body: body.compact }
  end

  # Pergunta que não recuperou nada é respondida sem chamar o modelo, e o uso
  # vem zerado: chamar aquilo de geração encheria o painel de chamadas que não
  # existiram.
  def generation?(span)
    usage = span[:usage] || {}

    usage[:prompt_tokens].to_i.positive? || usage[:completion_tokens].to_i.positive?
  end

  def billing(span)
    usage = span[:usage]

    { model: (span[:metadata] || {})[:model],
      usage: { input: usage[:prompt_tokens].to_i, output: usage[:completion_tokens].to_i, unit: TOKEN_UNIT } }
  end

  def ended_at(span)
    return nil if span[:started_at].nil? || span[:duration].nil?

    span[:started_at] + span[:duration]
  end

  def level_of(span)
    ERROR_LEVEL if span[:status] == :error
  end

  def iso(time)
    time&.utc&.iso8601(3)
  end
end
