# frozen_string_literal: true

require_relative 'qdrant_client'

# Reconstrói o índice léxico a partir dos pontos já guardados no Qdrant.
#
# Existe por causa de um defeito concreto, e barato de descrever: o `Bm25Index`
# vive em memória, então todo restart da API apagava o braço léxico da busca
# híbrida. A API subia saudável, respondia 200, e silenciosamente buscava só
# pelo vetor — com um embedder de hash no lugar de um modelo, isso é boa parte
# da qualidade indo embora sem nenhum sinal. A única volta era reingerir os
# documentos na mão.
#
# O texto de cada trecho já está no payload do Qdrant desde a ingestão. Ninguém
# o lia na partida; agora lê.
#
# Quatro decisões definem o comportamento:
#
# - **Reconstruir, e não persistir.** Guardar o índice em disco criaria um
#   segundo lugar onde a verdade mora, e os dois divergiriam no primeiro
#   documento apagado direto no Qdrant. O acervo é a fonte; o índice é derivado
#   dele e se refaz.
# - **Pagina, e não pede tudo de uma vez.** Um `limit` gigante troca o problema
#   de lugar: em vez de índice vazio, uma partida que consome o acervo inteiro
#   de uma vez na memória.
# - **Coleção inexistente não é erro.** Instalação nova não tem acervo, e
#   morrer no boot por causa disso deixaria a API sem subir justamente quando
#   não há nada a perder. Zero documentos é a resposta certa.
# - **Falha de transporte sobe.** Aqui não se decide política. Qdrant fora do ar
#   na partida é situação que quem monta a aplicação precisa ver para escolher
#   o que fazer — e escolhe no `Api.build`, que é onde as outras degradações do
#   projeto estão escritas.
class LexicalIndexLoader
  PAGE = 256
  EMPTY = { loaded: 0, complete: true, reason: nil }.freeze

  # Dois tetos, porque a varredura acontece **antes de o Puma abrir a porta**.
  # Sem eles, o conserto do índice teria trocado um defeito por outro pior:
  # "sobe e busca pela metade" viraria "não sobe" num acervo grande — e não
  # subir derruba readiness probe, estoura o `--wait` do compose e põe o
  # contêiner em loop de reinício.
  #
  # O teto de trechos limita o trabalho; o de tempo limita a espera mesmo com
  # um Qdrant lento respondendo pouco por página. Estourar qualquer um dos dois
  # **não é erro**: a API sobe com o índice parcial, que é melhor que índice
  # nenhum e muito melhor que não subir. O que não pode é isso passar
  # despercebido, e é o `complete: false` que carrega essa informação para
  # fora — junto do `reason:`, que diz **qual** dos dois tetos cortou. A
  # métrica não tem como carregar o motivo sem virar um rótulo por situação; o
  # log da partida carrega de graça.
  MAX_DOCUMENTS = 50_000
  TIMEOUT = 30

  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(qdrant:, index:, collection:, page: PAGE, max_documents: MAX_DOCUMENTS,
                 timeout: TIMEOUT, clock: MONOTONIC)
    @qdrant = qdrant
    @index = index
    @collection = collection
    @page = page
    @max_documents = max_documents
    @timeout = timeout
    @clock = clock
  end

  # Devolve `{ loaded:, complete:, reason: }`. `complete` falso significa que o
  # acervo é maior do que o que coube, e `reason` diz o que o cortou:
  # `:max_documents` ou `:timeout`. Quem chama decide o que fazer com isso — a
  # métrica publica o par para quem olha de fora, e o log da partida publica o
  # motivo.
  def load
    return EMPTY unless @qdrant.collection_exists?(@collection)

    walk(@clock.call + @timeout)
  end

  private

  # O prazo entra pronto, e não como duração: assim o relógio é lido uma vez no
  # começo e uma por página, e não duas por página para recalcular a mesma
  # conta.
  def walk(deadline)
    offset = nil
    loaded = 0

    loop do
      batch = @qdrant.scroll(@collection, limit: page_for(loaded), offset: offset)
      loaded += index_all(batch[:points])
      offset = batch[:next]
      return { loaded: loaded, complete: true, reason: nil } if offset.nil?
      return partial(loaded, :max_documents) if loaded >= @max_documents
      return partial(loaded, :timeout) if @clock.call >= deadline
    end
  end

  # Os dois tetos podem estourar na mesma página, e aí o motivo precisa ser
  # escolhido. O de trechos ganha por ser o **determinístico**: ele depende do
  # tamanho do acervo e vai estourar igual no próximo boot, enquanto o de tempo
  # depende de como o Qdrant estava naquele minuto. Culpar o relógio quando o
  # acervo também não cabia mandaria quem lê o log investigar latência de uma
  # partida que na verdade tem documento demais.
  def partial(loaded, reason)
    { loaded: loaded, complete: false, reason: reason }
  end

  # A última página vem menor para não passar do teto: pedir 256 quando faltam
  # 3 para o limite carregaria 253 trechos que a decisão já disse para não
  # carregar.
  def page_for(loaded)
    [@page, @max_documents - loaded].min
  end

  # Ponto sem texto no payload não tem o que indexar, e entrar como string
  # vazia sujaria a estatística de tamanho médio do BM25 — que é o que
  # normaliza o score de todo mundo.
  def index_all(points)
    points.count do |point|
      payload = point[:payload] || {}
      text = payload[:text].to_s
      next false if text.strip.empty?

      @index.add(point[:id], text, payload: payload)
      true
    end
  end
end
