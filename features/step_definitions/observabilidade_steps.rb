# frozen_string_literal: true

require 'json'
require 'stringio'

require_relative '../../lib/api/instrumentation'
require_relative '../../lib/api/metrics_endpoint'
require_relative '../../lib/api/request_logger'
require_relative '../../lib/metric_registry'
require_relative '../../lib/process_collector'

# Reaproveita `app`, `post_json` e os passos de chamada definidos em
# `api_steps.rb`: a pilha observada é a mesma API, com três middlewares a mais.
Dado('que a API observada está no ar com as chaves:') do |table|
  configuration = table.hashes.map { |row| "#{row['nome']}:#{row['chave']}:#{row['escopos']}" }.join(';')

  lexical_index = Bm25Index.new
  etl = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
    embedder: EmbeddingGenerator.new(dimensions: 64),
    lexical_index: lexical_index
  )
  rag = RagPipeline.new(
    retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
    llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 2
  )

  @registry = MetricRegistry.new
  Api::Instrumentation.install(@registry)
  ProcessCollector.new.install(@registry)
  @logs = StringIO.new

  authenticated = Api::Authentication.new(
    Api::MetricsEndpoint.new(
      Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION), registry: @registry
    ),
    store: ApiKeyStore.parse(configuration)
  )
  @app = Api::RequestLogger.new(
    Api::Instrumentation.new(authenticated, registry: @registry),
    io: @logs, route: Api::Instrumentation.method(:route_for)
  )
end

Então('a resposta deve conter a métrica {string}') do |metric|
  expect(last_response.body).to include(metric)
end

Então('a resposta não deve citar {string}') do |text|
  expect(last_response.body).not_to include(text)
end

Então('a resposta deve contar {int} requisição em {string} com status {string}') do |count, route, status|
  expect(last_response.body)
    .to include(%(aiad_http_requests_total{method="GET",route="#{route}",status="#{status}"} #{count}))
end

Então('o log deve ter {int} linha em JSON') do |lines|
  expect(@logs.string.lines.size).to eq(lines)
  expect { JSON.parse(@logs.string.lines.first) }.not_to raise_error
end

Então('a linha de log deve registrar a rota {string} com status {int}') do |route, status|
  expect(JSON.parse(@logs.string.lines.last)).to include('route' => route, 'status' => status)
end

Então('o log não deve conter {string}') do |text|
  expect(@logs.string).not_to include(text)
end

Então('a resposta deve trazer um id de requisição') do
  expect(last_response.headers['x-request-id']).not_to be_nil
end
