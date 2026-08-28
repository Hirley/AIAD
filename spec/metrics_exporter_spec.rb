# frozen_string_literal: true

require_relative '../lib/metrics_exporter'

RSpec.describe MetricsExporter do
  let(:prices) { { 'forte' => { input: 3.0, output: 15.0 } } }
  let(:metrics) { SessionMetrics.new(meter: UsageMeter.new(prices: prices)) }

  subject(:exporter) { described_class.new(metrics: metrics) }

  let(:tracer) { Tracer.new(exporter: exporter, clock: clock) }
  let(:ticks) { (0..50).to_a }
  let(:clock) { -> { ticks.shift.to_f } }

  def ask(session: 'sessao-1', model: 'forte', usage: { prompt_tokens: 80, completion_tokens: 20 })
    tracer.trace('rag.answer', input: '?', metadata: { session: session, model: model }) do |span|
      span.span('rag.retrieve') { 'trechos' }
      span.span('rag.generate') { |generation| generation.usage = usage }
    end
  end

  it 'counts one request per trace' do
    ask

    expect(metrics.for_session('sessao-1')[:requests]).to eq(1)
  end

  # A duração da raiz é o tempo da pergunta. Somar os spans contaria errado: há
  # tempo fora deles, e spans irmãos podem se sobrepor. Aqui o relógio anda seis
  # vezes (abre e fecha três spans), então a raiz mede 5 e a soma dos filhos, 2.
  it 'takes the latency from the root, not from the sum of the spans' do
    ask

    expect(metrics.for_session('sessao-1')[:latency][:total]).to eq(5.0)
  end
  # Um agente faz várias chamadas de modelo por pergunta; o gasto da pergunta é
  # a soma delas, onde quer que estejam na árvore.
  it 'adds up the token usage of the whole tree' do
    tracer.trace('agente', metadata: { session: 'sessao-1', model: 'forte' }) do |span|
      span.span('turno-1') { |turn| turn.usage = { prompt_tokens: 80, completion_tokens: 20 } }
      span.span('turno-2') do |turn|
        turn.span('aninhado') { |deep| deep.usage = { prompt_tokens: 10, completion_tokens: 5 } }
      end
    end

    expect(metrics.for_session('sessao-1')).to include(prompt_tokens: 90, completion_tokens: 25)
  end

  it 'files the request under the session in the trace metadata' do
    ask(session: 'sessao-2')

    expect(metrics.sessions).to eq(['sessao-2'])
  end

  it 'falls back to the no-session bucket when the trace was not labelled' do
    ask(session: nil)

    expect(metrics.for_session(SessionMetrics::NO_SESSION)[:requests]).to eq(1)
  end

  it 'charges the model named in the trace metadata' do
    ask(usage: { prompt_tokens: 1_000_000, completion_tokens: 1_000_000 })

    expect(metrics.for_session('sessao-1')[:cost]).to be_within(0.0001).of(18.0)
  end

  it 'breaks the usage down by model' do
    ask(model: 'barato')

    expect(metrics.by_model.keys).to eq(['barato'])
  end

  # Resposta de cache é rápida e não gasta token — e é exatamente o que se quer
  # ver no painel. Descartá-la esconderia o ganho do cache.
  it 'still counts a request that spent no tokens at all' do
    tracer.trace('rag.answer', metadata: { session: 'sessao-1' }) { 'do cache' }

    expect(metrics.for_session('sessao-1')).to include(requests: 1, total_tokens: 0)
  end

  it 'survives a trace with no metadata whatsoever' do
    expect { tracer.trace('solto') { 'ok' } }.not_to raise_error
  end
end
