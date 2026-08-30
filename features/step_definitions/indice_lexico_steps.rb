# frozen_string_literal: true

require 'json'
require 'stringio'

require_relative '../../lib/api/lexical_index_warmup'
require_relative '../../lib/bm25_index'
require_relative '../../lib/etl_pipeline'
require_relative '../../lib/metric_registry'
require_relative '../../lib/qdrant_client'
require_relative '../../spec/support/in_memory_qdrant_transport'

INDICE_COLECAO = 'documentos'

# Reiniciar é literalmente isto: índice novo, vazio, e a partida tendo de
# reconstruí-lo a partir do que ficou guardado.
#
# A partida passa pelo `Api::LexicalIndexWarmup`, e não pelo carregador cru.
# Aqui esteve a política de degradação **copiada** do `Api.build` — um `rescue`
# largo reproduzido no passo —, e cópia de política é onde a política some sem
# ninguém notar: o cenário seguiria verde enquanto o original mudasse.
def aquecer(env = {}, indice: Bm25Index.new)
  @transporte ||= InMemoryQdrantTransport.new
  @indice = indice
  @registro = MetricRegistry.new
  @log = StringIO.new
  @partida_falhou = false
  @resultado = Api::LexicalIndexWarmup.run(qdrant: QdrantClient.new(transport: @transporte),
                                           index: @indice, collection: INDICE_COLECAO,
                                           registry: @registro, env: env, logs: @log)
rescue StandardError
  @partida_falhou = true
end

def motivo_no_log
  JSON.parse(@log.string.lines.last).fetch('reason')
end

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

Quando('a API reinicia com o mesmo acervo') do
  aquecer
end

# O teto existe porque a varredura roda antes de a porta abrir: sem ele, acervo
# grande faria a API não subir, em vez de subir com metade da busca.
Quando('a API reinicia com teto de {int} trechos') do |teto|
  aquecer({ 'AIAD_LEXICAL_INDEX_MAX' => teto.to_s })
end

Quando('a API reinicia com o Qdrant fora do ar') do
  @transporte = TransporteForaDoAr.new
  aquecer
end

Quando('a API reinicia com um defeito no índice') do
  aquecer(indice: IndiceComDefeito.new)
end

Então('a busca léxica ainda deve encontrar {string}') do |termo|
  expect(@indice.search(termo)).not_to be_empty
end

Então('o índice léxico deve ter {int} trechos') do |quantidade|
  expect(@resultado[:loaded]).to eq(quantidade)
  expect(@indice.size).to eq(quantidade)
end

Então('o índice deve estar marcado como completo') do
  expect(@resultado[:complete]).to be(true)
end

Então('o índice deve estar marcado como parcial') do
  expect(@resultado[:complete]).to be(false)
end

Então('o log da partida deve dar {string} como motivo') do |motivo|
  expect(motivo_no_log).to eq(motivo)
end

Então('o log da partida não deve dar motivo nenhum') do
  expect(motivo_no_log).to be_nil
end

Então('o log da partida deve estar vazio') do
  expect(@log.string).to be_empty
end

Então('a partida não deve ter falhado') do
  expect(@partida_falhou).to be(false)
end

Então('a partida deve ter falhado') do
  expect(@partida_falhou).to be(true)
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

# Um defeito de programação no meio da varredura, que é o que o `rescue` largo
# engolia junto com o Qdrant fora do ar.
class IndiceComDefeito
  def add(*)
    raise NoMethodError, "undefined method 'text' for nil"
  end
end
