# frozen_string_literal: true

require_relative '../lexical_index_loader'

module Api
  # Reconstrói o índice léxico na partida e publica o tamanho dele como métrica.
  #
  # O `LexicalIndexLoader` sabe **como** varrer o acervo; aqui mora a política
  # de o que fazer quando isso não dá certo. Ficam separados porque as duas
  # coisas mudam por motivos diferentes: a varredura muda se o Qdrant mudar, a
  # política muda se a operação decidir que degradar em silêncio não serve mais.
  #
  # Duas decisões definem o comportamento:
  #
  # - **Qdrant fora do ar na partida não derruba a API.** É a mesma inversão do
  #   exportador de trace e do avaliador: quem observa, ou quem aquece, não
  #   derruba quem faz. O acervo inalcançável neste instante não é motivo para o
  #   processo não existir, e as rotas já sabem responder 503 quando a busca
  #   falha.
  # - **Mas a degradação não pode ser silenciosa.** Sem índice léxico a busca
  #   híbrida vira só o braço vetorial — e, com um embedder de hash no lugar de
  #   um modelo, isso é boa parte da qualidade indo embora com a API
  #   respondendo 200 o tempo todo. A métrica é o que torna isso visível:
  #   quem tem documento indexado e mede zero aqui está buscando pela metade.
  #
  # O que isto **não** resolve: o índice continua sendo uma cópia por processo.
  # Com `workers 0` no Puma, que é a configuração atual, há um processo só e a
  # cópia é única. Num deploy com vários workers cada um carregaria a sua —
  # iguais logo depois do boot, e divergindo a cada ingestão, porque só o worker
  # que atendeu o `POST /documents` indexa o trecho novo. Para valer ali, o
  # braço BM25 precisaria de um índice compartilhado ou dos vetores esparsos do
  # próprio Qdrant.
  module LexicalIndexWarmup
    METRIC = 'aiad_lexical_index_documents'
    HELP = 'Trechos carregados no índice léxico em memória.'

    def self.run(qdrant:, index:, collection:, registry:)
      registry.gauge(METRIC, help: HELP)
      loader = LexicalIndexLoader.new(qdrant: qdrant, index: index, collection: collection)

      registry.set(METRIC, loader.load)
    rescue StandardError
      registry.set(METRIC, 0)
    end
  end
end
