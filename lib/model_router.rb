# frozen_string_literal: true

require_relative 'token_counter'

# Roteamento de modelos: pergunta simples vai para o modelo barato, pergunta
# complexa vai para o caro.
#
# Expõe `complete(prompt)`, a mesma interface de um modelo, então entra no
# RagPipeline no lugar de um modelo único, sem nenhuma outra mudança.
#
# O classificador padrão olha tamanho do prompt e verbos que pedem raciocínio
# (comparar, analisar, explicar). Na dúvida, escolhe o modelo forte: errar para
# o lado caro custa dinheiro, errar para o lado barato custa uma resposta ruim.
class ModelRouter
  DEFAULT_THRESHOLD_TOKENS = 400
  REASONING = /\b(compar\w+|analis\w+|explic\w+|avali\w+|justific\w+|por que|porque)\b/i

  attr_reader :last_choice

  def initialize(fast:, strong:, classifier: nil, counter: TokenCounter.new,
                 threshold_tokens: DEFAULT_THRESHOLD_TOKENS)
    @fast = fast
    @strong = strong
    @classifier = classifier
    @counter = counter
    @threshold_tokens = threshold_tokens
    @last_choice = nil
  end

  def complete(prompt)
    @last_choice = choose(prompt)

    model_for(@last_choice).complete(prompt)
  end

  private

  def choose(prompt)
    choice = (@classifier || method(:classify)).call(prompt)

    %i[fast strong].include?(choice) ? choice : :strong
  end

  def classify(prompt)
    return :strong if @counter.estimate(prompt) > @threshold_tokens
    return :strong if REASONING.match?(prompt.to_s)

    :fast
  end

  def model_for(choice)
    choice == :fast ? @fast : @strong
  end
end
