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

  def initialize(qdrant:, index:, collection:, page: PAGE)
    @qdrant = qdrant
    @index = index
    @collection = collection
    @page = page
  end

  # Devolve quantos trechos entraram no índice.
  def load
    return 0 unless @qdrant.collection_exists?(@collection)

    offset = nil
    loaded = 0

    loop do
      batch = @qdrant.scroll(@collection, limit: @page, offset: offset)
      loaded += index_all(batch[:points])
      offset = batch[:next]
      break if offset.nil?
    end

    loaded
  end

  private

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
