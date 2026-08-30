# frozen_string_literal: true

require_relative 'relevance_floor'

# Publica as notas de avaliação no registro de métricas, cumprindo a mesma
# interface do `EvaluationLog` — `record(question:, answer:, scores:)`. Entra no
# `EvaluatedRag` no lugar dele, ou ao lado, sem que o decorador saiba a
# diferença.
#
# Quatro decisões definem o comportamento:
#
# - **Histograma, não média.** A média de sustentação esconde o que interessa:
#   noventa respostas perfeitas e dez inventadas dão 0,9, que parece ótimo. A
#   distribuição mostra a segunda corcova. E o `_sum` com o `_count` continua
#   dando a média para quem quiser.
# - **Uma lista de baldes por nota, e não uma compartilhada.** As três medem
#   coisas com formas diferentes, e o detalhe está em cada constante abaixo.
# - **Pergunta e resposta não viram métrica.** Só a nota atravessa. Texto de
#   usuário como rótulo seria cardinalidade infinita — e, pior, o conteúdo da
#   pergunta acabaria guardado para sempre num sistema que ninguém trata como
#   base de dados pessoais. O texto fica no log e no `EvaluationLog`, que são
#   os lugares certos para lê-lo.
# - **Frase não sustentada tem contador próprio.** A nota diz o quanto piorou;
#   o contador diz quantas afirmações sem apoio saíram para o usuário, que é o
#   número que se leva para uma conversa sobre risco.
class PrometheusEvaluationLog
  SCORES = {
    groundedness: 'aiad_llm_groundedness',
    answer_relevancy: 'aiad_llm_answer_relevancy',
    context_relevancy: 'aiad_llm_context_relevancy'
  }.freeze

  EVALUATED = 'aiad_llm_evaluated_answers_total'
  UNSUPPORTED = 'aiad_llm_unsupported_sentences_total'

  # A lista antiga era uma só para as três notas — `[0.25, 0.5, 0.75, 0.9,
  # 0.95, 0.99, 1.0]` — e o comentário ao lado dizia que os cortes eram
  # apertados perto de 1 porque "a diferença entre 0,95 e 1,0 é a que importa".
  #
  # O erro não estava no gosto, estava na aritmética. **As três notas são
  # razões de inteiros pequenos**: sustentação é `k/n` com `n` = frases da
  # resposta; relevância da resposta é `k/|Q|` com `|Q|` = termos de conteúdo
  # da pergunta; relevância de contexto é a média de `k/|Q|` sobre os trechos.
  # Para uma nota cair **entre 0,9 e 1,0** é preciso denominador ≥ 11 — onze
  # frases numa resposta, onze termos de conteúdo numa pergunta. As respostas
  # daqui têm de uma a quatro frases. Os três cortes apertados no topo
  # descreviam, portanto, uma faixa que a conta não consegue povoar: pediam
  # resolução onde não há valor nenhum, e deixavam sem resolução a faixa onde
  # os valores realmente caem.
  #
  # O `le=0.25` era o caso extremo, e por outro motivo: com o piso de
  # relevância ligado (o padrão), nenhum trecho abaixo de `DEFAULT_MINIMUM`
  # chega à avaliação, então a média deles também não desce até lá.
  #
  # Os cortes abaixo saem dessa derivação, não de gosto. A medição na stack
  # serve para confirmar a forma de cada nota, e não para escolher corte por
  # frequência: seis perguntas contra três documentos é amostra pequena demais
  # para isso, e vale dizer o que ela mostrou.
  #
  # Sustentação saiu 6/6 em 1,0. Não é a métrica indo bem: o `ExtractiveLlm`,
  # que é o padrão, recorta o trecho em vez de reescrevê-lo, então a resposta é
  # substring literal do contexto e a nota não tem como não ser 1. **A corcova
  # de baixo só aparece com um modelo que parafraseie** — o painel novo mostra
  # uma linha reta até a #26 ligar um. Relevância de resposta e de contexto
  # saíram idênticas, cinco amostras em 1,0 e uma em 0,571: com um trecho
  # recuperado e resposta extrativa, as duas medem literalmente a mesma
  # sobreposição. Nenhuma amostra de contexto desceu abaixo de 0,65, o que é
  # coerente com o piso — e com o `le=0.25` que nunca recebeu nada.
  #
  # **Sustentação: bimodal, e o que importa é o tamanho de cada corcova.** A
  # nota é léxica, então resposta extrativa tira 1,0 e paráfrase correta tira
  # 0,0, sem meio-termo (o limite está medido no cabeçalho do
  # `AnswerEvaluator`). O corte em **0,0** é a mudança que mais rende: antes, a
  # corcova do "nada se sustenta" caía dentro do `le=0.25` junto com 1/4 e 1/5,
  # e não dava para ler o tamanho dela. Agora `le=0` é só ela, e a outra
  # corcova é `_count` menos `le=0.9`. Não há corte acima de 0,9 porque, com
  # até dez frases, não existe nota ali.
  GROUNDEDNESS_BUCKETS = [0.0, 0.25, 0.5, 0.75, 0.9, 1.0].freeze

  # **Relevância da resposta: a única que se espalha de verdade hoje.** Cortes
  # uniformes de 0,2 porque cinco amostras não sustentam favorecer nenhuma
  # parte da faixa — assimetria aqui seria exatamente o palpite que esta
  # mudança existe para tirar. O corte em 0,0 separa "a resposta não divide
  # termo nenhum com a pergunta", que é outra falha (respondeu outra coisa), de
  # "respondeu em parte".
  ANSWER_RELEVANCY_BUCKETS = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0].freeze

  # **Relevância de contexto: a faixa começa no piso, e o primeiro corte é o
  # piso.** O `RelevanceFloor` só deixa passar trecho com cobertura ≥
  # `DEFAULT_MINIMUM`, e a nota é a média dessas coberturas, então com o padrão
  # ligado ela vive em [0,45; 1,00]. Usar a constante em vez de escrever 0,45
  # amarra as duas coisas: mexer no piso move o histograma junto, em vez de
  # criar um balde morto novo em silêncio.
  #
  # Dois limites conhecidos, e nenhum dos dois justifica corte abaixo do piso:
  # com `AIAD_RELEVANCE_FLOOR=0` a nota volta a poder descer, e tudo abaixo de
  # 0,45 se amontoa no balde de baixo; e o `PromptCompressor`, quando nem um
  # trecho cabe no orçamento, corta o texto do primeiro (`truncated: true`)
  # depois de o piso já ter pontuado o texto inteiro — o que pode render uma
  # nota abaixo do piso mesmo com ele ligado. Os dois caem no balde de baixo,
  # que é o lugar honesto para "isto não deveria estar aqui".
  CONTEXT_RELEVANCY_BUCKETS = [RelevanceFloor::DEFAULT_MINIMUM, 0.55, 0.65, 0.75, 0.85, 0.95, 1.0].freeze

  BUCKETS = {
    groundedness: GROUNDEDNESS_BUCKETS,
    answer_relevancy: ANSWER_RELEVANCY_BUCKETS,
    context_relevancy: CONTEXT_RELEVANCY_BUCKETS
  }.freeze

  HELP = {
    groundedness: 'Fração das frases da resposta sustentadas pelo contexto.',
    answer_relevancy: 'Quanto a resposta trata da pergunta feita.',
    context_relevancy: 'Quanto do contexto recuperado tem a ver com a pergunta.'
  }.freeze

  def self.install(registry)
    SCORES.each do |score, name|
      registry.histogram(name, help: HELP.fetch(score), buckets: BUCKETS.fetch(score))
    end
    registry.counter(EVALUATED, help: 'Respostas avaliadas.')
    registry.counter(UNSUPPORTED, help: 'Frases que saíram sem apoio no contexto.')

    registry
  end

  def initialize(registry:)
    @registry = registry
  end

  # `question` e `answer` chegam e não são usados de propósito: a assinatura é
  # a do `EvaluationLog`, e é ela que permite trocar um pelo outro. Usar o
  # texto aqui é justamente o que não se quer.
  def record(question:, answer:, scores:)
    SCORES.each { |score, name| @registry.observe(name, scores[score].to_f) if scores.key?(score) }
    @registry.increment(EVALUATED)
    @registry.increment(UNSUPPORTED, by: scores[:unsupported].to_a.size)
  end
end
