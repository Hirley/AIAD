# frozen_string_literal: true

require_relative '../lib/answer_evaluator'

RSpec.describe AnswerEvaluator do
  subject(:evaluator) { described_class.new }

  let(:passages) do
    [{ text: 'A política de férias garante trinta dias por ano.', source: 'politica.txt' },
     { text: 'As férias podem ser divididas em três períodos.', source: 'ferias.txt' }]
  end

  def evaluate(answer, question: 'quantos dias de férias por ano?')
    evaluator.evaluate(question: question, answer: answer, passages: passages)
  end

  describe 'groundedness' do
    it 'gives full marks to an answer the context sustains' do
      expect(evaluate('A política garante trinta dias por ano.')[:groundedness]).to eq(1.0)
    end

    # O marcador de citação quebra como se fosse uma frase, e sozinho não tem
    # apoio em lugar nenhum. Contá-lo punia a resposta por fazer exatamente o
    # que se pede que ela faça: citar a origem.
    it 'does not punish an answer for carrying the citation marker' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:groundedness]).to eq(1.0)
    end

    it 'does not count the citation marker as a sentence' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:sentences]).to eq(1)
    end

    it 'keeps the marker out of the unsupported list' do
      expect(evaluate('A política garante trinta dias por ano. [1]')[:unsupported]).to be_empty
    end

    it 'gives zero to an answer the context says nothing about' do
      expect(evaluate('O reajuste salarial sai em dezembro.')[:groundedness]).to eq(0.0)
    end

    # Uma resposta com três frases certas e uma inventada precisa pontuar no
    # meio: é o grau que diz se a qualidade caiu, não um booleano.
    it 'scores sentence by sentence instead of all or nothing' do
      answer = 'A política garante trinta dias por ano. O reajuste salarial sai em dezembro.'

      expect(evaluate(answer)[:groundedness]).to be_within(0.001).of(0.5)
    end

    # O número sozinho não diz o que revisar.
    it 'names the sentences that do not stand up' do
      answer = 'A política garante trinta dias por ano. O reajuste salarial sai em dezembro.'

      expect(evaluate(answer)[:unsupported]).to eq(['O reajuste salarial sai em dezembro.'])
    end

    # Afirmar sem nada em que se apoiar é não-sustentado por definição. Devolver
    # 1 por vacuidade esconderia exatamente o caso que se quer pegar.
    it 'gives zero when there was no context at all' do
      report = evaluator.evaluate(question: 'quantos dias?', answer: 'Trinta dias.', passages: [])

      expect(report[:groundedness]).to eq(0.0)
    end

    it 'gives zero to an empty answer' do
      expect(evaluate('')[:groundedness]).to eq(0.0)
    end

    # Palavra funcional aparece em qualquer trecho e sustentaria qualquer coisa.
    it 'ignores stopwords when deciding what is supported' do
      expect(evaluate('De a para com por.')[:groundedness]).to eq(0.0)
    end
  end

  describe 'answer relevancy' do
    it 'gives full marks to an answer that speaks to the question' do
      expect(evaluate('São trinta dias de férias por ano.')[:answer_relevancy]).to eq(1.0)
    end

    it 'gives zero to an answer about something else entirely' do
      expect(evaluate('O escritório fica na avenida central.')[:answer_relevancy]).to eq(0.0)
    end
  end

  describe 'context relevancy' do
    def relevancy(*texts, question: 'quantos dias de férias por ano?')
      sources = texts.each_with_index.map { |text, index| { text: text, source: "#{index}.txt" } }

      evaluator.evaluate(question: question, answer: 'Trinta.', passages: sources)[:context_relevancy]
    end

    it 'gives full marks when every term of the question is in the context' do
      expect(relevancy('A política de férias garante trinta dias por ano.')).to eq(1.0)
    end

    it 'is zero when nothing was retrieved' do
      expect(relevancy).to eq(0.0)
    end

    it 'is zero when what was retrieved has nothing to do with the question' do
      expect(relevancy('O café acaba às dez.')).to eq(0.0)
    end

    # Média da sobreposição, e não a fração dos trechos que sobrepõem em alguma
    # medida. Os três trechos abaixo casam 3/3, 1/3 e 0/3 dos termos de
    # conteúdo da pergunta: a contagem antiga daria 2/3, porque dois deles
    # sobrepõem "em alguma medida"; a média dá 0,44, que é o quanto do contexto
    # de fato serve.
    it 'averages how much each passage matches instead of counting the ones that match at all' do
      relevancia = relevancy('A política de férias garante trinta dias por ano.',
                             'As férias podem ser divididas em três períodos.',
                             'O café acaba às dez.')

      expect(relevancia).to be_within(0.001).of(4.0 / 9)
    end

    # A razão de ser da mudança. O `RelevanceFloor` roda antes e só deixa passar
    # trecho a partir de 0,45 de cobertura; a contagem antiga chamava de
    # relevante qualquer sobreposição maior que zero. Passar no piso implicava
    # passar aqui, e a nota ficava presa em 1,0 — inclusive quando o piso estava
    # mal calibrado e mantinha trecho ruim, que é justamente o que ela existe
    # para denunciar.
    it 'reports a low score for a passage that only barely clears the floor' do
      relevancia = relevancy('As férias podem ser divididas em três períodos.')

      expect(relevancia).to be < 0.5
    end
  end

  # Sustentação aqui é sobreposição de vocabulário. Para resposta extrativa as
  # duas coisas coincidem — o `ExtractiveLlm` devolve substring literal do
  # contexto, e por isso a nota na stack é 1,0 sempre. Para resposta gerada,
  # não coincidem, e o preço está medido abaixo.
  #
  # Estes exemplos afirmam o **limite**, não o desejado: existem para que quem
  # plugar um modelo de verdade descubra isso por teste, e não por painel
  # acusando alucinação onde não há. O conserto é o `judge:`, e o último
  # exemplo mostra que a costura funciona.
  describe 'the known limit of lexical grounding' do
    let(:contexto) do
      [{ text: 'A política de férias da empresa garante trinta dias corridos por ano a todo empregado ' \
               'com mais de doze meses de casa.', source: 'politica.txt' }]
    end

    def grounded(answer, judge: nil)
      avaliador = judge ? described_class.new(judge: judge) : evaluator

      avaliador.evaluate(question: 'quantos dias de férias por ano?', answer: answer,
                         passages: contexto)[:groundedness]
    end

    let(:parafrase) { 'O colaborador tem direito a um mês inteiro de descanso remunerado a cada período aquisitivo.' }
    let(:alucinacao) { 'O reajuste salarial sai em dezembro para todos os cargos.' }

    it 'gives full marks to an answer that reuses the words of the context' do
      expect(grounded('A política garante trinta dias corridos por ano.')).to eq(1.0)
    end

    # O caso que importa: as duas frases abaixo tiram a mesma nota, e uma delas
    # está certa. Não é o limiar que está errado — é a medida, que não vê
    # sinônimo. Um limiar mais baixo aprovaria a alucinação junto.
    it 'cannot tell a correct paraphrase from a fabrication' do
      expect(grounded(parafrase)).to eq(grounded(alucinacao))
    end

    # E por que baixar o `SUPPORT_THRESHOLD` não resolve: afrouxar o corte
    # aprova a alucinação **antes** de aprovar a paráfrase certa, porque a
    # paráfrase reaproveita ainda menos palavras. As faixas não são vizinhas,
    # são sobrepostas, e nenhum corte as separa na ordem que se quer.
    it 'approves the fabrication before the paraphrase as the threshold drops' do
      frouxo = described_class.new(threshold: 0.15)
      nota = lambda do |answer|
        frouxo.evaluate(question: 'quantos dias?', answer: answer, passages: contexto)[:groundedness]
      end

      expect([nota.call(parafrase), nota.call(alucinacao)]).to eq([0.0, 1.0])
    end

    # A saída que o desenho já previa. Um juiz que entende sinônimo separa os
    # dois casos sem que nada mais mude.
    it 'separates them again once a real judge is injected' do
      judge = ->(sentence, _context) { sentence == parafrase ? 1.0 : 0.0 }

      expect([grounded(parafrase, judge: judge), grounded(alucinacao, judge: judge)]).to eq([1.0, 0.0])
    end
  end

  # Mesmo padrão do Reranker: a heurística é o padrão barato, e um juiz de
  # verdade (LLM-as-judge, cross-encoder) entra por injeção sem mexer em quem
  # chama.
  describe 'with an injected judge' do
    subject(:evaluator) { described_class.new(judge: ->(_claim, _context) { 1.0 }) }

    it 'uses the judge to decide whether a sentence stands up' do
      expect(evaluate('Qualquer invenção sobre qualquer assunto.')[:groundedness]).to eq(1.0)
    end

    it 'hands the judge the sentence and the context' do
      seen = []
      evaluator = described_class.new(judge: ->(claim, context) { seen << [claim, context] and 1.0 })
      evaluator.evaluate(question: '?', answer: 'Trinta dias.', passages: passages)

      expect(seen.first.first).to eq('Trinta dias.')
      expect(seen.first.last).to include('trinta dias por ano')
    end
  end

  it 'reports how many sentences it looked at' do
    expect(evaluate('Uma frase. Outra frase.')[:sentences]).to eq(2)
  end
end
