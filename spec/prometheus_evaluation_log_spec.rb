# frozen_string_literal: true

require_relative '../lib/evaluated_rag'
require_relative '../lib/metric_registry'
require_relative '../lib/relevance_floor'
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

  # A lista de baldes era uma só para as três notas, e três dos sete cortes
  # ficavam numa faixa que a aritmética das notas não consegue povoar. O
  # detalhe da derivação está no cabeçalho da classe; aqui ficam os exemplos
  # que falham se alguém devolver um corte para lá.
  describe 'os baldes' do
    # Sustentação e relevância da resposta são razões de inteiros pequenos:
    # `k/n` com `n` = frases da resposta, `k/|Q|` com `|Q|` = termos de
    # conteúdo da pergunta. Isto reconstrói o que essas contas conseguem
    # produzir com denominador até dez.
    def razoes
      (1..10).flat_map { |denominador| (0..denominador).map { |numerador| numerador.fdiv(denominador) } }.uniq
    end

    def baldes_sem_valor_possivel(cortes)
      ([-Float::INFINITY] + cortes).each_cons(2)
                                   .reject { |baixo, alto| razoes.any? { |v| v > baixo && v <= alto } }
                                   .map(&:last)
    end

    it 'gives each score its own cuts, because the three have different shapes' do
      expect(described_class::BUCKETS.values.uniq.size).to eq(3)
    end

    # Era o defeito da lista antiga: `le=0.95` e `le=0.99` exigem denominador
    # maior que dez -- onze frases numa resposta -- para receber uma amostra.
    it 'has no groundedness bucket the arithmetic of the score cannot reach' do
      expect(baldes_sem_valor_possivel(described_class::BUCKETS.fetch(:groundedness))).to be_empty
    end

    it 'has no answer relevancy bucket the arithmetic of the score cannot reach' do
      expect(baldes_sem_valor_possivel(described_class::BUCKETS.fetch(:answer_relevancy))).to be_empty
    end

    # A relevância de contexto é a **média** das coberturas, então tem
    # granularidade mais fina que uma razão só e não passa pela conta acima. O
    # que a torna alcançável é outra coisa: o piso. Nenhum trecho abaixo dele
    # chega à avaliação, e média de valores ≥ 0,45 é ≥ 0,45 -- um corte abaixo
    # disso nasceria morto, que é o que este exemplo impede.
    it 'has no context relevancy cut below the floor that filters the passages' do
      expect(described_class::BUCKETS.fetch(:context_relevancy).min).to be >= RelevanceFloor::DEFAULT_MINIMUM
    end

    # O que a mudança compra na prática: a corcova do "nada se sustenta" deixa
    # de dividir balde com "uma frase de quatro se sustenta". São diagnósticos
    # diferentes -- modelo inventando tudo, contra modelo inventando um pedaço
    # -- e o painel não conseguia separar os dois.
    it 'keeps the hallucination hump in a bucket of its own' do
      record(groundedness: 0.0, answer_relevancy: 1.0, context_relevancy: 1.0, unsupported: %w[a])
      record(groundedness: 0.25, answer_relevancy: 1.0, context_relevancy: 1.0, unsupported: %w[a b c])

      expect(registry.render).to include("aiad_llm_groundedness_bucket{le=\"0\"} 1\n",
                                         "aiad_llm_groundedness_bucket{le=\"0.25\"} 2\n")
    end

    it 'starts the context relevancy histogram at the floor, not at zero' do
      record(groundedness: 1.0, answer_relevancy: 1.0, context_relevancy: 0.5, unsupported: [])

      expect(registry.render).to include("aiad_llm_context_relevancy_bucket{le=\"0.45\"} 0\n")
      expect(registry.render).not_to include('aiad_llm_context_relevancy_bucket{le="0"}')
    end
  end
end
