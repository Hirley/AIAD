# frozen_string_literal: true

require_relative '../lib/usage_meter'

RSpec.describe UsageMeter do
  subject(:meter) { described_class.new(prices: { 'modelo-caro' => { input: 3.0, output: 15.0 } }) }

  describe '#record' do
    it 'returns the usage of the call' do
      usage = meter.record(model: 'modelo-caro', prompt_tokens: 1000, completion_tokens: 500)

      expect(usage).to include(prompt_tokens: 1000, completion_tokens: 500, total_tokens: 1500)
    end

    it 'prices the call by the configured rate per million tokens' do
      usage = meter.record(model: 'modelo-caro', prompt_tokens: 1_000_000, completion_tokens: 1_000_000)

      expect(usage[:cost]).to be_within(0.0001).of(18.0)
    end

    it 'charges nothing for a model without a configured price' do
      expect(meter.record(model: 'desconhecido', prompt_tokens: 100, completion_tokens: 100)[:cost]).to eq(0.0)
    end
  end

  describe '#totals' do
    it 'accumulates across calls' do
      meter.record(model: 'modelo-caro', prompt_tokens: 100, completion_tokens: 50)
      meter.record(model: 'modelo-caro', prompt_tokens: 200, completion_tokens: 100)

      expect(meter.totals).to include(calls: 2, prompt_tokens: 300, completion_tokens: 150, total_tokens: 450)
    end

    it 'starts at zero' do
      expect(meter.totals).to include(calls: 0, total_tokens: 0, cost: 0.0)
    end
  end

  describe '#by_model' do
    it 'breaks the usage down per model' do
      meter.record(model: 'modelo-caro', prompt_tokens: 100, completion_tokens: 10)
      meter.record(model: 'outro', prompt_tokens: 50, completion_tokens: 5)

      expect(meter.by_model.keys).to contain_exactly('modelo-caro', 'outro')
      expect(meter.by_model['outro'][:total_tokens]).to eq(55)
    end
  end
end

# O preço nunca chegava ao exportador: o `Api::Observability` montava o
# `PrometheusTraceExporter` sem `prices:`, e o custo saía zero mesmo com o
# modelo cobrando. A tabela agora vem do ambiente, e a leitura dela mora aqui,
# junto com a conta que a usa.
RSpec.describe UsageMeter, '.prices_from_env' do
  it 'reads a price table in dollars per million tokens' do
    prices = described_class.prices_from_env({ 'AIAD_MODEL_PRICES' => 'claude-sonnet-5:3:15' })

    expect(prices).to eq('claude-sonnet-5' => { input: 3.0, output: 15.0 })
  end

  it 'reads more than one model, separated like the api keys are' do
    prices = described_class.prices_from_env({ 'AIAD_MODEL_PRICES' => 'forte:3:15;barato:0.8:4' })

    expect(prices.keys).to contain_exactly('forte', 'barato')
  end

  # Sem configuração o custo é zero explícito, e quem avisa que isso está
  # acontecendo é a linha de partida do `Api::Observability`, não uma tabela
  # embutida que envelheceria em silêncio.
  it 'is empty when nothing is configured, instead of guessing a price' do
    expect(described_class.prices_from_env({})).to be_empty
  end

  # Configuração errada derruba a partida, como a linha de chaves do
  # ApiKeyStore: preço é configuração, e surpreender quem pergunta é pior do
  # que não subir.
  it 'refuses a price that is not a number' do
    expect { described_class.prices_from_env({ 'AIAD_MODEL_PRICES' => 'forte:tres:15' }) }
      .to raise_error(described_class::ConfigurationError, /não numérico/)
  end

  it 'refuses an entry with a missing price' do
    expect { described_class.prices_from_env({ 'AIAD_MODEL_PRICES' => 'forte:3' }) }
      .to raise_error(described_class::ConfigurationError, /faltando/)
  end

  # A conta que já existia passa a receber a tabela lida do ambiente, e é este
  # o caminho inteiro que estava roto: ambiente -> tabela -> custo.
  it 'feeds the cost calculation it already knew how to do' do
    prices = described_class.prices_from_env({ 'AIAD_MODEL_PRICES' => 'forte:3:15' })

    expect(described_class.cost_of(prices, 'forte', 1_000_000, 1_000_000)).to eq(18.0)
  end
end
