# frozen_string_literal: true

require_relative '../lib/evaluated_rag'

RSpec.describe EvaluatedRag do
  let(:hits) do
    [{ id: 1, score: 0.92, payload: { text: 'A política garante trinta dias de férias por ano.',
                                      source: 'politica.txt' } }]
  end
  let(:llm) { FakeLlm.new(response: 'A política garante trinta dias por ano.') }
  let(:rag) { RagPipeline.new(retriever: FakeRetriever.new(results: hits), llm: llm, collection: 'documentos') }
  let(:log) { EvaluationLog.new }

  subject(:evaluated) { described_class.new(rag: rag, log: log) }

  it 'answers exactly what the pipeline answered' do
    expect(evaluated.answer('quantos dias de férias?')[:answer]).to eq('A política garante trinta dias por ano.')
  end

  it 'attaches the scores to the answer' do
    expect(evaluated.answer('quantos dias de férias?')[:evaluation]).to include(:groundedness,
                                                                                :answer_relevancy,
                                                                                :context_relevancy)
  end

  it 'records every answer in the log' do
    evaluated.answer('quantos dias de férias?')

    expect(log.averages[:samples]).to eq(1)
  end

  it 'scores an answer the context sustains' do
    expect(evaluated.answer('quantos dias de férias?')[:evaluation][:groundedness]).to eq(1.0)
  end

  it 'catches an answer the context does not sustain' do
    invented = described_class.new(rag: RagPipeline.new(retriever: FakeRetriever.new(results: hits),
                                                        llm: FakeLlm.new(response: 'O reajuste sai em dezembro.'),
                                                        collection: 'documentos'), log: log)

    expect(invented.answer('quantos dias de férias?')[:evaluation][:groundedness]).to eq(0.0)
  end

  # Sem contexto o RagPipeline nem chama o modelo: não há o que alucinar.
  # Pontuar zero aqui encheria o painel de falso positivo.
  describe 'when there was nothing to answer from' do
    subject(:evaluated) do
      described_class.new(rag: RagPipeline.new(retriever: FakeRetriever.new(results: []), llm: llm,
                                               collection: 'documentos'), log: log)
    end

    it 'does not score the answer' do
      expect(evaluated.answer('quantos dias?')).not_to have_key(:evaluation)
    end

    it 'does not put it in the log either' do
      evaluated.answer('quantos dias?')

      expect(log.averages[:samples]).to eq(0)
    end
  end

  # Mesma inversão do exportador de trace: quem observa não derruba quem faz.
  describe 'when the evaluator blows up' do
    subject(:evaluated) do
      described_class.new(rag: rag, log: log, evaluator: Class.new { def evaluate(**) = raise('quebrou') }.new)
    end

    it 'still answers' do
      expect(evaluated.answer('quantos dias?')[:answer]).to eq('A política garante trinta dias por ano.')
    end

    it 'answers without a score rather than not at all' do
      expect(evaluated.answer('quantos dias?')).not_to have_key(:evaluation)
    end
  end

  it 'passes the metadata filter through to the pipeline' do
    retriever = FakeRetriever.new(results: hits)
    described_class.new(rag: RagPipeline.new(retriever: retriever, llm: llm, collection: 'documentos'), log: log)
                   .answer('quantos dias?', filter: { autor: 'rh' })

    expect(retriever.calls.last[:filter]).to eq(autor: 'rh')
  end
end
