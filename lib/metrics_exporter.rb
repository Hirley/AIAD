# frozen_string_literal: true

require_relative 'session_metrics'
require_relative 'tracer'

# Exportador de trace que alimenta o `SessionMetrics`: tudo que já está
# instrumentado vira medição sem uma linha a mais no código instrumentado.
#
# É o mesmo encaixe do exportador para um coletor externo — só que o destino é
# local. Um trace pode ir para os dois: um manda para o Langfuse, o outro
# alimenta o painel do Grafana.
#
# Três decisões que definem o comportamento:
#
# - **A latência é a duração da raiz.** Somar os spans contaria errado: há
#   tempo fora deles (montar prompt, serializar) e spans irmãos podem se
#   sobrepor. O que o usuário esperou é o intervalo da raiz.
# - **O uso soma a árvore inteira.** Um agente gasta várias chamadas de modelo
#   para responder uma pergunta, algumas em spans aninhados fundo; o gasto da
#   pergunta é a soma de todas.
# - **Trace sem token nenhum também é requisição.** Resposta de cache é rápida
#   e de graça, e é exatamente o que se quer ver no painel: descartá-la
#   esconderia o ganho do cache.
#
# Limite conhecido: o modelo é lido dos metadados do trace, um por pergunta.
# Enquanto o roteamento de modelos não estiver ligado na API isso é exato, já
# que cada pergunta usa um modelo só. Quando estiver, um trace que misture dois
# modelos vai atribuir o gasto inteiro ao rótulo declarado — e aí a quebra por
# modelo precisa passar a sair dos spans de geração, não da raiz.
class MetricsExporter
  def initialize(metrics: SessionMetrics.new)
    @metrics = metrics
  end

  def export(trace)
    metadata = trace[:metadata] || {}
    usage = total_usage(trace)

    @metrics.record(session: metadata[:session], model: metadata[:model], latency: trace[:duration].to_f,
                    prompt_tokens: usage[:prompt_tokens], completion_tokens: usage[:completion_tokens])
  end

  private

  def total_usage(span)
    children = (span[:spans] || []).map { |nested| total_usage(nested) }
    own = span[:usage] || {}

    children.each_with_object(prompt_tokens: own[:prompt_tokens].to_i,
                              completion_tokens: own[:completion_tokens].to_i) do |nested, sum|
      sum[:prompt_tokens] += nested[:prompt_tokens]
      sum[:completion_tokens] += nested[:completion_tokens]
    end
  end
end
