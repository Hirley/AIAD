# frozen_string_literal: true

require 'json'

require_relative '../../lib/api/instrumentation'
require_relative '../../lib/composite_exporter'
require_relative '../../lib/langfuse_exporter'
require_relative '../../lib/metric_registry'
require_relative '../../lib/prometheus_trace_exporter'
require_relative '../../lib/tracer'
require_relative '../../spec/support/fake_http_client'

# Reaproveita `app`, `post_json` e os passos de chamada de `api_steps.rb`: a
# pilha rastreada é a mesma API, com um exportador a mais pendurado no tracer.
def build_traced_api(langfuse:)
  @langfuse_transport = FakeHttpClient.new(code: '207', body: JSON.generate(successes: []))
  @registry = MetricRegistry.new
  PrometheusTraceExporter.install(@registry)

  # O Langfuse vem primeiro de propósito. É a ordem em que a queda dele
  # poderia cortar a entrega ao Prometheus — com ele em segundo, o cenário da
  # métrica passaria mesmo que o composto parasse no primeiro erro, e um
  # cenário que não consegue falhar não está guardando nada.
  exporter = CompositeExporter.for(
    (LangfuseExporter.new(public_key: 'pk', secret_key: 'sk', client: @langfuse_transport) if langfuse),
    PrometheusTraceExporter.new(registry: @registry)
  )

  @app = traced_stack(Tracer.new(exporter: exporter))
end

TRACED_KEYS = 'leitor:chave-leitura:read;ingestor:chave-escrita:read,write'

def traced_stack(tracer)
  lexical_index = Bm25Index.new
  etl = EtlPipeline.new(qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
                        embedder: EmbeddingGenerator.new(dimensions: 64), lexical_index: lexical_index)
  rag = RagPipeline.new(retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
                        llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 2, tracer: tracer)

  Api::Authentication.new(Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION),
                          store: ApiKeyStore.parse(TRACED_KEYS))
end

# Tudo o que subiu para o Langfuse, achatado: os cenários perguntam pelos
# eventos, não pela divisão em lotes.
def langfuse_events
  @langfuse_transport.requests.flat_map do |request|
    JSON.parse(request.body, symbolize_names: true)[:batch]
  end
end

def langfuse_events_of(type)
  langfuse_events.select { |event| event[:type] == type }
end

Dado('que a API rastreada está no ar com o Langfuse configurado') do
  build_traced_api(langfuse: true)
end

Dado('que a API rastreada está no ar sem o Langfuse configurado') do
  build_traced_api(langfuse: false)
end

Dado('que um documento já foi ingerido') do
  post_json('/documents', { content: DOCUMENTO, source: 'politica.txt' }, 'chave-escrita')
end

Dado('que o Langfuse está fora do ar') do
  @langfuse_transport.offline!
end

Então('o Langfuse deve ter recebido {int} trace') do |count|
  expect(langfuse_events_of('trace-create').size).to eq(count)
end

Então('o trace deve registrar a pergunta {string}') do |question|
  expect(langfuse_events_of('trace-create').first[:body][:input]).to eq(question)
end

Então('o trace deve registrar a resposta que a API devolveu') do
  expect(langfuse_events_of('trace-create').first[:body][:output].to_s).to include(json_response['answer'])
end

Então('o Langfuse deve ter recebido {int} geração') do |count|
  expect(langfuse_events_of('generation-create').size).to eq(count)
end

Então('a geração deve declarar os tokens gastos') do
  expect(langfuse_events_of('generation-create').first[:body][:usage][:input]).to be_positive
end

Então('o Langfuse deve ter recebido a observação {string}') do |name|
  expect(langfuse_events_of('span-create').map { |event| event[:body][:name] }).to include(name)
end

Então('toda observação deve apontar para o trace') do
  trace_id = langfuse_events_of('trace-create').first[:body][:id]
  observations = langfuse_events.reject { |event| event[:type] == 'trace-create' }

  expect(observations.map { |event| event[:body][:traceId] }).to all(eq(trace_id))
end

Então('o Prometheus deve ter contado a chamada ao modelo') do
  expect(@registry.render).to match(/#{PrometheusTraceExporter::CALLS}\{[^}]*\} [1-9]/)
end

Então('o Langfuse não deve ter recebido nada') do
  expect(@langfuse_transport.requests).to be_empty
end
