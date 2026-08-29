# frozen_string_literal: true

require_relative '../../lib/bm25_index'
require_relative '../../lib/etl_pipeline'
require_relative '../../lib/lexical_index_loader'
require_relative '../../lib/qdrant_client'
require_relative '../../spec/support/in_memory_qdrant_transport'

INDICE_COLECAO = 'documentos'

# O transporte sobrevive ao "restart", e o índice não — que é exatamente o
# desenho real: o Qdrant é um serviço à parte, com volume, e o `Bm25Index` mora
# na memória do processo que morreu.
Dado('que o acervo tem o documento {string} com {string}') do |origem, texto|
  @transporte ||= InMemoryQdrantTransport.new
  @indice ||= Bm25Index.new
  etl = EtlPipeline.new(qdrant: QdrantClient.new(transport: @transporte),
                        embedder: EmbeddingGenerator.new(dimensions: 64),
                        lexical_index: @indice)

  etl.run(texto, collection: INDICE_COLECAO, source: origem)
end

Dado('que a busca léxica encontra {string}') do |termo|
  expect(@indice.search(termo)).not_to be_empty
end

# Reiniciar é literalmente isto: índice novo, vazio, e o carregador tendo de
# reconstruí-lo a partir do que ficou guardado.
Quando('a API reinicia com o mesmo acervo') do
  @transporte ||= InMemoryQdrantTransport.new
  @indice = Bm25Index.new
  @carregados = LexicalIndexLoader.new(qdrant: QdrantClient.new(transport: @transporte),
                                       index: @indice, collection: INDICE_COLECAO).load
end

Quando('a API reinicia com o Qdrant fora do ar') do
  @indice = Bm25Index.new
  carregador = LexicalIndexLoader.new(qdrant: QdrantClient.new(transport: TransporteForaDoAr.new),
                                      index: @indice, collection: INDICE_COLECAO)

  # A política de degradação é a do `Api.build`, reproduzida aqui: o erro sobe
  # do carregador e quem monta a aplicação decide não morrer por causa dele.
  @carregados = begin
    carregador.load
  rescue StandardError
    0
  end
  @partida_falhou = false
end

Então('a busca léxica ainda deve encontrar {string}') do |termo|
  expect(@indice.search(termo)).not_to be_empty
end

Então('o índice léxico deve ter {int} trechos') do |quantidade|
  expect(@carregados).to eq(quantidade)
  expect(@indice.size).to eq(quantidade)
end

Então('a partida não deve ter falhado') do
  expect(@partida_falhou).to be(false)
end

# Recusa toda chamada, como um Qdrant que não atende.
class TransporteForaDoAr
  FORA = { ok: false }.freeze

  def get(_path) = FORA
  def put(_path, _body = nil) = FORA
  def post(_path, _body = nil) = FORA
  def patch(_path, _body = nil) = FORA
  def delete(_path) = FORA
end
