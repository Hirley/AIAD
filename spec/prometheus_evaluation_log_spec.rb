# frozen_string_literal: true

require_relative '../lib/evaluated_rag'
require_relative '../lib/metric_registry'
require_relative '../lib/prometheus_evaluation_log'

RSpec.describe PrometheusEvaluationLog do
  let(:registry) { described_class.install(MetricRegistry.new) }

  subject(:log) { described_class.new(registry: registry) }

  def record(scores)
    log.record(question: 'quantos dias de férias', answer: 'trinta dias', scores: scores)
  end

  describe '#record' do
    before do
      record(groundedness: 1.0, answer_relevancy: 1.0, context_relevancy: 0.5, unsupported: [])
    end

    it 'publishes each score on its own metric, because they fail for different reasons' do
      expect(registry.render).to include('aiad_llm_groundedness_sum 1',
                                         'aiad_llm_answer_relevancy_sum 1',
                                         'aiad_llm_context_relevancy_sum 0.5')
    end

    it 'counts the evaluated answers, which is the denominator of every average' do
      expect(registry.render).to include("aiad_llm_evaluated_answers_total 1\n")
    end

    it 'publishes a distribution, not just an average' do
      expect(registry.render).to include('aiad_llm_groundedness_bucket')
    end
  end

  # A nota diz o quanto piorou; o contador diz quantas afirmações sem apoio
  # saíram para o usuário.
  describe 'frases sem apoio' do
    it 'counts them' do
      record(groundedness: 0.5, answer_relevancy: 1.0, context_relevancy: 1.0,
             unsupported: ['O prazo é de sessenta dias.', 'A adesão é opcional.'])

      expect(registry.render).to include("aiad_llm_unsupported_sentences_total 2\n")
    end

    it 'stays at zero when everything was supported' do
      record(groundedness: 1.0, answer_relevancy: 1.0, context_relevancy: 1.0, unsupported: [])

      expect(registry.render).to include("aiad_llm_unsupported_sentences_total 0\n")
    end
  end

  # Texto de usuário como rótulo seria cardinalidade infinita — e o conteúdo da
  # pergunta acabaria guardado para sempre num sistema que ninguém trata como
  # base de dados pessoais.
  describe 'o que não vira métrica' do
    it 'keeps the question out of the metrics' do
      log.record(question: 'meu CPF é 000.000.000-00?', answer: 'não sei', scores: { groundedness: 1.0 })

      expect(registry.render).not_to include('000.000.000-00')
    end

    it 'keeps the answer out of the metrics' do
      log.record(question: 'pergunta', answer: 'segredo industrial', scores: { groundedness: 1.0 })

      expect(registry.render).not_to include('segredo industrial')
    end
  end

  # Cumpre a mesma interface do EvaluationLog, então entra no lugar dele.
  describe 'como log do EvaluatedRag' do
    it 'is fed by the decorator without it knowing the difference' do
      rag = instance_double(RagPipeline, answer: { question: 'q', answer: 'trinta dias por ano',
                                                   passages: [{ text: 'trinta dias por ano', source: 'a.txt' }] })
      EvaluatedRag.new(rag: rag, log: log).answer('q')

      expect(registry.render).to include("aiad_llm_evaluated_answers_total 1\n")
    end
  end
end
