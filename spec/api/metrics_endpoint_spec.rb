# frozen_string_literal: true

require 'rack/test'

require_relative '../../lib/api/metrics_endpoint'
require_relative '../../lib/metric_registry'
require_relative '../../lib/prometheus_exposition'

RSpec.describe Api::MetricsEndpoint do
  include Rack::Test::Methods

  let(:registry) do
    MetricRegistry.new.tap do |metrics|
      metrics.counter('aiad_x_total', help: 'Um contador.')
      metrics.increment('aiad_x_total')
    end
  end
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['aplicação']] } }

  def app
    described_class.new(downstream, registry: registry)
  end

  describe 'GET /metrics' do
    it 'answers with the rendered registry' do
      get '/metrics'

      expect(last_response.body).to include("aiad_x_total 1\n")
    end

    it 'announces the content type the Prometheus expects' do
      get '/metrics'

      expect(last_response.headers['content-type']).to eq(PrometheusExposition::CONTENT_TYPE)
    end

    it 'answers 200' do
      get '/metrics'

      expect(last_response.status).to eq(200)
    end
  end

  describe 'as outras rotas' do
    it 'passes everything else through to the application' do
      get '/health'

      expect(last_response.body).to eq('aplicação')
    end

    # O caminho sozinho não basta: POST /metrics é outra coisa, e cai na
    # aplicação como qualquer rota desconhecida.
    it 'only answers to GET' do
      post '/metrics'

      expect(last_response.body).to eq('aplicação')
    end
  end
end
