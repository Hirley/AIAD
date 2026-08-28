# frozen_string_literal: true

require 'rack/test'

require_relative '../../lib/api/instrumentation'
require_relative '../../lib/metric_registry'

RSpec.describe Api::Instrumentation do
  include Rack::Test::Methods

  let(:registry) { Api::Instrumentation.install(MetricRegistry.new) }
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:clock) { [0.0, 0.2] }

  def app
    described_class.new(downstream, registry: registry, clock: -> { clock.shift })
  end

  describe 'contagem' do
    it 'counts the request by method, route and status' do
      post '/ask'

      expect(registry.render).to include(%(aiad_http_requests_total{method="POST",route="/ask",status="200"} 1\n))
    end

    it 'separates status codes, so a spike of errors is visible' do
      allow(downstream).to receive(:call).and_return([500, {}, []])
      post '/ask'

      expect(registry.render).to include(%(status="500"))
    end
  end

  # Um varredor pedindo mil caminhos inventados criaria mil séries temporais
  # permanentes. Com a normalização ele cria uma.
  describe 'cardinalidade' do
    it 'collapses an unknown path into a single label' do
      get '/nao-existe'

      expect(registry.render).to include(%(route="outra"))
    end

    it 'does not let the raw path into a label' do
      get '/caminho-inventado-por-um-varredor'

      expect(registry.render).not_to include('caminho-inventado')
    end

    it 'knows the routes declared in the access policy, without a second list' do
      expect(described_class::KNOWN_ROUTES).to include('/ask', '/health', '/metrics')
    end
  end

  describe 'duração' do
    it 'observes the request duration in the histogram' do
      post '/ask'

      expect(registry.render).to include(%(aiad_http_request_duration_seconds_sum{method="POST",route="/ask"} 0.2\n))
    end

    it 'reports buckets, so the percentile is chosen when the panel is read' do
      post '/ask'

      expect(registry.render).to include('aiad_http_request_duration_seconds_bucket')
    end
  end

  describe 'requisições em andamento' do
    it 'is back to zero once the request is done' do
      post '/ask'

      expect(registry.render).to include("aiad_http_requests_in_flight 0\n")
    end

    it 'counts the request while it runs' do
      medido = nil
      inner = lambda { |_env|
        medido = registry.render
        [200, {}, []]
      }
      described_class.new(inner, registry: registry, clock: -> { 0.0 }).call('REQUEST_METHOD' => 'GET',
                                                                             'PATH_INFO' => '/health')

      expect(medido).to include("aiad_http_requests_in_flight 1\n")
    end
  end

  describe 'quando o app estoura' do
    let(:downstream) { ->(_env) { raise 'falhou' } }

    it 'lets the exception through, because observing is not deciding' do
      expect { app.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ask') }.to raise_error('falhou')
    end

    it 'counts the exception on its own metric, instead of inventing a status nobody returned' do
      begin
        app.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ask')
      rescue RuntimeError
        nil
      end

      expect(registry.render).to include(%(aiad_http_exceptions_total{route="/ask"} 1\n))
    end

    # Requisição lenta que estourou é justamente a que se quer ver no gráfico.
    it 'still records the duration' do
      begin
        app.call('REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/ask')
      rescue RuntimeError
        nil
      end

      expect(registry.render).to include(%(aiad_http_request_duration_seconds_count{method="GET",route="/ask"} 1\n))
    end
  end
end
