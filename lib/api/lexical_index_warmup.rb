# frozen_string_literal: true

require 'json'
require 'time'

require_relative '../lexical_index_loader'
require_relative '../qdrant_client'

module Api
  # Reconstrói o índice léxico na partida, publica o que aconteceu como métrica
  # e escreve uma linha de log dizendo o que foi.
  #
  # O `LexicalIndexLoader` sabe **como** varrer o acervo; aqui mora a política
  # de o que fazer quando isso não dá certo. Ficam separados porque as duas
  # coisas mudam por motivos diferentes: a varredura muda se o Qdrant mudar, a
  # política muda se a operação decidir que degradar em silêncio não serve mais.
  #
  # Cinco decisões definem o comportamento:
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
  # - **Erro inesperado sobe, e derruba a partida.** É a decisão que faltava
  #   estar escrita, e a que reverteu um `rescue StandardError` que engolia
  #   tudo. Qdrant fora do ar é operacional e esperado; `NoMethodError` no meio
  #   da varredura é defeito meu, e virava `documents 0` com `complete 0`,
  #   indistinguível de indisponibilidade de infraestrutura — um disfarce
  #   durável, que sobrevive semanas porque a API responde 200 o tempo todo.
  #   Morrer no boot com o stack trace na saída é a mesma escolha que o
  #   `Console` já faz quando a página não veio na imagem: falhar na montagem,
  #   e não na primeira visita, quando ninguém mais está lendo o log de
  #   partida. E o CI sobe a stack a cada PR, então o defeito reprova o PR em
  #   vez de degradar em produção.
  # - **O que se espera é só `RequestError`.** Não há lista de erro de rede
  #   aqui, e não é esquecimento: o `HttpQdrantTransport` já converte toda
  #   falha de `Net::HTTP` — recusa de conexão, timeout, DNS — em
  #   `{ ok: false }`, e o `QdrantClient` transforma isso em `RequestError`.
  #   Rescatar `Errno::ECONNREFUSED` neste ponto seria rescatar o que não
  #   chega, e código que se defende do impossível se lê como se o possível
  #   estivesse coberto.
  # - **Nada disso pode ser silencioso, e métrica sozinha é silêncio.** Sem
  #   índice léxico a busca híbrida vira só o braço vetorial — e, com um
  #   embedder de hash no lugar de um modelo, isso é boa parte da qualidade
  #   indo embora com a API respondendo 200. As duas métricas contam quantos
  #   trechos entraram e se isso é o acervo inteiro, mas ninguém olha painel
  #   durante um boot: quem sobe o contêiner lê log. Por isso sai uma linha por
  #   partida, no mesmo stream e no mesmo formato JSON do `RequestLogger`, e é
  #   ela que carrega o **motivo** — a informação que a métrica não tem como
  #   levar sem virar um rótulo por situação.
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

    EVENT = 'lexical_index_warmup'
    UNREACHABLE = { loaded: 0, complete: false, reason: :unreachable }.freeze
    NOW = -> { Time.now.utc }

    def self.run(qdrant:, index:, collection:, registry:, env: ENV, logs: $stdout)
      install(registry)
      result = load_index(qdrant, index, collection, env)
      report(registry, result)
      log(logs, result)

      result
    end

    # O `rescue` cobre a leitura do acervo, e só ela. O que sobe daqui é o que
    # não estava previsto, e é justamente o que não pode virar `documents 0`.
    def self.load_index(qdrant, index, collection, env)
      loader(qdrant, index, collection, env).load
    rescue QdrantClient::RequestError
      UNREACHABLE
    end
    private_class_method :load_index

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

    # `reason` fica na linha mesmo quando é nulo: esquema estável é o que
    # deixa `jq` e Loki filtrarem por motivo sem tratar a chave ausente como um
    # caso à parte.
    #
    # O `sync` é pelo mesmo motivo do `RequestLogger`: a saída padrão de um
    # contêiner não é terminal, então sai bufferizada em blocos — e uma linha
    # de partida que aparece minutos depois da partida, ou nunca se o processo
    # morrer antes, não serve para nada.
    def self.log(logs, result)
      logs.sync = true if logs.respond_to?(:sync=)
      logs.write("#{JSON.generate(entry(result))}\n")
    end
    private_class_method :log

    def self.entry(result)
      {
        ts: NOW.call.iso8601,
        level: result[:complete] ? 'info' : 'warn',
        event: EVENT,
        documents: result[:loaded],
        complete: result[:complete],
        reason: result[:reason]
      }
    end
    private_class_method :entry
  end
end
