# frozen_string_literal: true

require_relative '../../lib/rag_pipeline'
require_relative '../../lib/relevance_floor'
require_relative '../../lib/reranker'

# Os documentos são os mesmos com que o defeito foi encontrado rodando a stack:
# três políticas que não se sobrepõem, e perguntas cuja resposta não está em
# nenhuma delas.
POLITICAS = [
  ['politica-ferias.txt',
   'A política de férias garante trinta dias corridos por ano a todo empregado com mais de doze meses ' \
   'de casa. As férias podem ser divididas em até três períodos.'],
  ['politica-trabalho-remoto.txt',
   'O regime de trabalho remoto é permitido em até três dias por semana. O auxílio home office é de ' \
   'duzentos reais mensais.'],
  ['politica-reembolso.txt',
   'O reembolso de despesas de viagem cobre passagem, hospedagem e alimentação. Toda despesa exige ' \
   'nota fiscal legível.']
].freeze

def build_api_with_floor(floor)
  lexical_index = Bm25Index.new
  etl = EtlPipeline.new(qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
                        embedder: EmbeddingGenerator.new(dimensions: 64), lexical_index: lexical_index)
  rag = RagPipeline.new(retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
                        llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 3,
                        reranker: Reranker.new, relevance_floor: floor)

  Api::Authentication.new(Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION),
                          store: ApiKeyStore.parse(TRACED_KEYS))
end

# Montar a aplicação e ingerir num passo só, e não em dois, porque o
# Rack::Test memoiza a sessão na primeira aplicação que vê: um cenário que
# trocasse de aplicação no meio continuaria falando com a antiga em silêncio.
def start_api_with_floor(floor)
  @app = build_api_with_floor(floor)

  POLITICAS.each do |source, content|
    post_json('/documents', { content: content, source: source }, 'chave-escrita')
  end
end

Dado('que a API com piso de relevância está no ar com as políticas ingeridas') do
  start_api_with_floor(RelevanceFloor.new)
end

Dado('que a API sem piso de relevância está no ar com as políticas ingeridas') do
  start_api_with_floor(nil)
end

Então('a resposta deve dizer que não encontrou') do
  expect(json_response['answer']).to eq(RagPipeline::NO_CONTEXT_ANSWER)
end

Então('a resposta não deve citar origem nenhuma') do
  expect(json_response['sources']).to be_empty
end

Então('a resposta deve citar alguma origem') do
  expect(json_response['sources']).not_to be_empty
end

Então('a resposta da API não deve citar a origem {string}') do |source|
  expect(json_response['sources']).not_to include(source)
end

Então('a resposta não deve ter gasto token nenhum') do
  expect(json_response['usage']['total_tokens']).to eq(0)
end
