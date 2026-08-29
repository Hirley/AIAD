# frozen_string_literal: true

require_relative '../lexical_index_loader'

module Api
  # Reconstrói o índice léxico na partida e publica o que aconteceu como
  # métrica.
  #
  # O `LexicalIndexLoader` sabe **como** varrer o acervo; aqui mora a política
  # de o que fazer quando isso não dá certo. Ficam separados porque as duas
  # coisas mudam por motivos diferentes: a varredura muda se o Qdrant mudar, a
  # política muda se a operação decidir que degradar em silêncio não serve mais.
  #
  # Três decisões definem o comportamento:
  #
  # - **Qdrant fora do ar na partida não derruba a API.** É a mesma inversão do
  #   exportador de trace e do avaliador: quem observa, ou quem aquece, não
  #   derruba quem faz. O acervo inalcançável neste instante não é motivo para o
  #   processo não existir, e as rotas já sabem responder 503 quando a busca
  #   falha.
  # - **Acervo maior que o teto também não derruba.** A varredura acontece antes
  #   de o Puma abrir a porta, então um acervo grande sem teto transformaria
  #   "sobe e busca pela metade" em "não sobe" — que é pior. Estourando o teto
  #   de trechos ou o de tempo, a API sobe com o índice parcial.
  # - **Mas nada disso pode ser silencioso.** Sem índice léxico a busca híbrida
  #   vira só o braço vetorial — e, com um embedder de hash no lugar de um
  #   modelo, isso é boa parte da qualidade indo embora com a API respondendo
  #   200 o tempo todo. Duas métricas contam a história inteira: quantos trechos
  #   entraram, e se isso é o acervo inteiro ou só o que coube.
  #
  # O que isto **não** resolve, e vale saber antes de mexer no `workers` do
  # Puma: o índice é uma estrutura na memória do processo. Hoje há `workers 0` e
  # `preload_app!`, então ele é montado uma vez e ponto. Com vários workers o
  # `preload_app!` faria o aquecimento rodar **uma vez só, no master**, e os
  # workers herdariam o índice pronto pelo fork — o custo de partida não se
  # multiplicaria. O que se quebra não é a carga, é o que vem depois: cada
  # ingestão é atendida por um worker só, e a partir da primeira as cópias
  # divergem em silêncio. Para valer ali, o braço BM25 precisaria de um índice
  # compartilhado ou dos vetores esparsos do próprio Qdrant.
  module LexicalIndexWarmup
    METRIC = 'aiad_lexical_index_documents'
    COMPLETE = 'aiad_lexical_index_complete'
    HELP = 'Trechos carregados no índice léxico em memória.'
    COMPLETE_HELP = '1 quando o índice cobre o acervo inteiro; 0 quando parou no teto ou falhou.'

    def self.run(qdrant:, index:, collection:, registry:, env: ENV)
      install(registry)
      report(registry, loader(qdrant, index, collection, env).load)
    rescue StandardError
      report(registry, LexicalIndexLoader::EMPTY.merge(loaded: 0, complete: false))
    end

    def self.install(registry)
      registry.gauge(METRIC, help: HELP)
      registry.gauge(COMPLETE, help: COMPLETE_HELP)
    end
    private_class_method :install

    def self.loader(qdrant, index, collection, env)
      LexicalIndexLoader.new(
        qdrant: qdrant, index: index, collection: collection,
        max_documents: Integer(env.fetch('AIAD_LEXICAL_INDEX_MAX', LexicalIndexLoader::MAX_DOCUMENTS)),
        timeout: Integer(env.fetch('AIAD_LEXICAL_INDEX_TIMEOUT', LexicalIndexLoader::TIMEOUT))
      )
    end
    private_class_method :loader

    def self.report(registry, result)
      registry.set(METRIC, result[:loaded])
      registry.set(COMPLETE, result[:complete] ? 1 : 0)
    end
    private_class_method :report
  end
end
