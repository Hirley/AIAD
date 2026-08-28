# frozen_string_literal: true

require_relative '../lib/session_metrics'

RSpec.describe SessionMetrics do
  let(:prices) { { 'forte' => { input: 3.0, output: 15.0 } } }

  subject(:metrics) { described_class.new(meter: UsageMeter.new(prices: prices)) }

  def record(session: 'sessao-1', model: 'forte', prompt: 1000, completion: 1000, latency: 1.0)
    metrics.record(session: session, model: model, prompt_tokens: prompt,
                   completion_tokens: completion, latency: latency)
  end

  describe 'per session' do
    it 'counts the requests' do
      2.times { record }

      expect(metrics.for_session('sessao-1')[:requests]).to eq(2)
    end

    it 'accumulates the tokens' do
      record(prompt: 80, completion: 20)
      record(prompt: 40, completion: 10)

      expect(metrics.for_session('sessao-1')).to include(prompt_tokens: 120, completion_tokens: 30,
                                                         total_tokens: 150)
    end

    # O preço por milhão de tokens já está no UsageMeter; duplicar a conta aqui
    # seria ter dois lugares para errar.
    it 'accumulates the cost the meter computed' do
      record(prompt: 1_000_000, completion: 1_000_000)

      expect(metrics.for_session('sessao-1')[:cost]).to be_within(0.0001).of(18.0)
    end

    it 'keeps sessions apart' do
      record(session: 'sessao-1')
      record(session: 'sessao-2')

      expect(metrics.for_session('sessao-1')[:requests]).to eq(1)
    end

    # Dashboard pergunta por sessão que ainda não existe o tempo todo.
    it 'answers zero for a session that never happened' do
      expect(metrics.for_session('nunca-vista')).to include(requests: 0, total_tokens: 0, cost: 0.0)
    end

    it 'lists the sessions it saw' do
      record(session: 'sessao-1')
      record(session: 'sessao-2')

      expect(metrics.sessions).to contain_exactly('sessao-1', 'sessao-2')
    end

    # Perder a medição por falta de rótulo é pior do que medir num balde só.
    it 'files a request with no session under a bucket of its own' do
      record(session: nil)

      expect(metrics.for_session(described_class::NO_SESSION)[:requests]).to eq(1)
    end
  end

  describe 'latency' do
    # O que o usuário sente é o tempo da pergunta inteira, não o de cada
    # chamada de modelo: um agente faz várias por pergunta.
    it 'accumulates the total time' do
      record(latency: 0.4)
      record(latency: 0.6)

      expect(metrics.for_session('sessao-1')[:latency][:total]).to be_within(0.0001).of(1.0)
    end

    it 'averages over the requests' do
      record(latency: 0.4)
      record(latency: 0.6)

      expect(metrics.for_session('sessao-1')[:latency][:average]).to be_within(0.0001).of(0.5)
    end

    it 'keeps the worst one' do
      record(latency: 0.4)
      record(latency: 2.1)

      expect(metrics.for_session('sessao-1')[:latency][:max]).to be_within(0.0001).of(2.1)
    end

    it 'reports the 95th percentile by nearest rank' do
      (1..20).each { |value| record(latency: value.to_f) }

      expect(metrics.for_session('sessao-1')[:latency][:p95]).to be_within(0.0001).of(19.0)
    end

    # Com uma amostra só, p95 é a própria amostra. Vale dizer no teste para
    # ninguém ler o número como estatística.
    it 'degenerates to the only sample it has' do
      record(latency: 0.4)

      expect(metrics.for_session('sessao-1')[:latency][:p95]).to be_within(0.0001).of(0.4)
    end

    it 'is all zero for a session that never happened' do
      expect(metrics.for_session('nunca-vista')[:latency]).to eq(total: 0.0, average: 0.0, max: 0.0, p95: 0.0)
    end
  end

  describe 'across every session' do
    it 'adds up the totals' do
      record(session: 'sessao-1', prompt: 80, completion: 20, latency: 0.4)
      record(session: 'sessao-2', prompt: 40, completion: 10, latency: 0.6)

      expect(metrics.totals).to include(requests: 2, total_tokens: 150)
    end

    it 'averages the latency over every request, not over the sessions' do
      record(session: 'sessao-1', latency: 0.4)
      record(session: 'sessao-1', latency: 0.6)
      record(session: 'sessao-2', latency: 2.0)

      expect(metrics.totals[:latency][:average]).to be_within(0.0001).of(1.0)
    end

    # A quebra por modelo é a que responde "vale a pena rotear para o barato?".
    it 'hands the per-model breakdown over from the meter' do
      record(model: 'forte')
      record(model: 'barato')

      expect(metrics.by_model.keys).to contain_exactly('forte', 'barato')
    end
  end

  it 'returns the usage of the call it just recorded' do
    expect(record(prompt: 80, completion: 20)).to include(total_tokens: 100)
  end
end
