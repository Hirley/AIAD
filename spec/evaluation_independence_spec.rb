# frozen_string_literal: true

require_relative '../lib/answer_evaluator'
require_relative '../lib/relevance_floor'
require_relative '../lib/tokenizer'

# O piso decide o que entra no contexto. O avaliador mede o quanto do contexto
# prestava. São papéis opostos de propósito: um filtra, o outro fiscaliza o
# filtro — e uma fiscalização que usa o critério do fiscalizado não fiscaliza
# nada.
#
# Era o que acontecia. O `RelevanceFloor` mantém o trecho a partir de 0,45 de
# cobertura, e o `AnswerEvaluator#context_relevancy` chamava o trecho de
# relevante com sobreposição **maior que zero** — a mesma fração, pela mesma
# tokenização e pelo mesmo `Stemmer`. Passar no piso implicava passar no
# avaliador, e a nota não conseguia valer outra coisa que 1,0.
#
# Medido na stack: cinco respostas avaliadas, cinco amostras exatamente em 1,0,
# nenhuma no balde de 0,99. Medido aqui: dezesseis mil perguntas geradas, um
# único valor. A métrica que existe para avisar "a recuperação está trazendo
# lixo" tinha perdido a capacidade de avisar, porque quem definia lixo era a
# mesma conta que o piso havia usado para manter.
#
# Estes exemplos existem para que isso não volte. Duas decisões:
#
# - **A propriedade é informação, não desacordo.** Não se exige que o avaliador
#   reprove o que o piso aprovou; exige-se que a nota **possa variar**. Sempre
#   1,0 pode ser piso perfeito ou instrumento quebrado, e é essa ambiguidade
#   que não pode existir num painel.
# - **Nenhum dos exemplos afirma como consertar.** Média de sobreposição —
#   que foi o caminho tomado —, cross-encoder, juiz por LLM ou qualquer
#   heurística que não seja a contagem antiga satisfazem igualmente. O que a
#   spec proíbe é a nota voltar a ser consequência aritmética do piso.
RSpec.describe 'independência entre o piso e a avaliação' do
  subject(:floor) { RelevanceFloor.new }

  let(:evaluator) { AnswerEvaluator.new }

  def passage(text, source:)
    { text: text, source: source, score: 0.03 }
  end

  let(:passages) do
    [passage('A política de férias garante trinta dias corridos por ano a todo empregado com mais de doze meses ' \
             'de casa. As férias podem ser divididas em até três períodos.', source: 'ferias.txt'),
     passage('O trabalho remoto é permitido em até três dias por semana para engenharia e produto. O auxílio ' \
             'home office é de duzentos reais mensais.', source: 'remoto.txt'),
     passage('O reembolso de despesas de viagem cobre passagem, hospedagem e alimentação. O adiantamento de ' \
             'viagem pode ser solicitado com dez dias úteis de antecedência.', source: 'reembolso.txt')]
  end

  # A nota não depende da resposta, só da pergunta e do contexto. Passar um
  # texto qualquer aqui deixa isso explícito.
  def context_relevancy(question, kept)
    evaluator.evaluate(question: question, answer: 'irrelevante para esta nota.', passages: kept)[:context_relevancy]
  end

  def surviving_scores(questions)
    questions.filter_map do |question|
      kept = floor.apply(question, passages)
      context_relevancy(question, kept) unless kept.empty?
    end
  end

  # A forma direta: percorrer perguntas escritas à mão e ver se existe **uma**
  # em que a nota não sai cheia. Se o piso aprova e o avaliador sempre dá nota
  # máxima, a implicação é total e a nota é decorativa.
  describe 'the evaluator as an instrument separate from the filter' do
    let(:questions) do
      ['quantos dias de férias por ano',
       'posso dividir as férias em períodos',
       'quantos dias de trabalho remoto por semana',
       'qual o valor do auxílio home office',
       'o reembolso cobre hospedagem',
       'com quanta antecedência peço adiantamento de viagem',
       'férias e reembolso de viagem no mesmo ano',
       'trabalho remoto do exterior precisa de aprovação',
       'quantos dias corridos de antecedência',
       'dias de viagem e dias de férias',
       'empregado com doze meses de casa',
       'auxílio para alimentação em viagem']
    end

    it 'can score context the floor approved as less than fully relevant' do
      expect(surviving_scores(questions)).to include(a_value < 1.0)
    end
  end

  # A forma estatística, que foi como o defeito apareceu: gerar pergunta a
  # partir do vocabulário do acervo e de fora dele, e olhar a distribuição.
  # Uma métrica que só consegue emitir um valor não carrega informação
  # nenhuma, e o painel que a exibe está desenhando uma constante.
  describe 'the distribution the histogram receives' do
    let(:samples) { 300 }
    let(:seed) { 20_260_829 }

    # Palavras que o acervo não cobre. Existem para que a busca também produza
    # pergunta ruim, que é o caso em que a nota deveria cair.
    let(:outside) { %w[odontológico plano saúde sindicato demissão bônus creche estágio ponto] }

    let(:vocabulary) do
      passages.flat_map { |candidate| Tokenizer.meaningful(candidate[:text]) }.uniq + outside
    end

    let(:random_questions) do
      random = Random.new(seed)

      Array.new(samples) do
        Array.new(random.rand(1..6)) { vocabulary.sample(random: random) }.uniq.join(' ')
      end
    end

    it 'takes more than one value' do
      expect(surviving_scores(random_questions).uniq.size).to be > 1
    end
  end
end
