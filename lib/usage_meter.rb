# frozen_string_literal: true

# Contabilidade de uso: quantos tokens cada chamada gastou, quanto custou e
# como isso se acumula por modelo.
#
# Os preços são informados em dólares por milhão de tokens, que é como os
# provedores publicam. Modelo sem preço configurado entra com custo zero, para
# que o esquecimento apareça como zero explícito e não quebre a requisição.
class UsageMeter
  class ConfigurationError < StandardError; end

  PER_MILLION = 1_000_000.0
  ENV_VAR = 'AIAD_MODEL_PRICES'

  # Formato: `modelo:entrada:saida`, em dólares por milhão de tokens,
  # separados por ponto e vírgula -- a mesma forma do `AIAD_API_KEYS`, para não
  # existirem duas convenções de configuração no mesmo `.env`.
  #
  # **Não há tabela embutida, e isso é decisão.** Preço de provedor muda, e uma
  # tabela no código envelheceria em silêncio: custo errado com cara de certo é
  # pior do que custo zero, porque ninguém confere um número plausível.
  # Configuração ausente dá custo zero — e o boot diz isso em voz alta quando
  # há modelo de verdade configurado, para o zero não se passar por "saiu de
  # graça".
  #
  # Entrada malformada estoura na partida, e não na primeira pergunta: o mesmo
  # que o `ApiKeyStore` faz com a linha de chaves. Preço é configuração, e
  # configuração errada tem de derrubar quem sobe, não surpreender quem usa.
  def self.prices_from_env(env = ENV)
    env[ENV_VAR].to_s.split(';').map(&:strip).reject(&:empty?).to_h do |entry|
      model, input, output = entry.split(':').map(&:to_s).map(&:strip)

      [model, { input: price!(entry, input), output: price!(entry, output) }]
    end
  end

  def self.price!(entry, value)
    raise ConfigurationError, "preço faltando em #{entry.inspect}" if value.to_s.empty?

    Float(value)
  rescue ArgumentError
    raise ConfigurationError, "preço não numérico em #{entry.inspect}: #{value.inspect}"
  end
  private_class_method :price!

  def initialize(prices: {})
    @prices = prices
    @calls = []
  end

  def record(model:, prompt_tokens:, completion_tokens:)
    usage = {
      model: model,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens,
      cost: cost_of(model, prompt_tokens, completion_tokens)
    }
    @calls << usage

    usage
  end

  def totals
    @calls.each_with_object(empty_totals.merge(calls: @calls.size)) do |usage, totals|
      accumulate(totals, usage)
    end
  end

  def by_model
    @calls.group_by { |usage| usage[:model] }.transform_values do |usages|
      usages.each_with_object(empty_totals.merge(calls: usages.size)) { |usage, totals| accumulate(totals, usage) }
    end
  end

  # Método de classe porque não é só este medidor que precisa da conta: o
  # exportador para o Prometheus calcula o mesmo custo sem acumular nada em
  # memória. Duas implementações de "quanto custou" divergiriam na primeira
  # mudança de tabela de preço.
  def self.cost_of(prices, model, prompt_tokens, completion_tokens)
    price = prices[model]
    return 0.0 if price.nil?

    ((prompt_tokens * price[:input].to_f) + (completion_tokens * price[:output].to_f)) / PER_MILLION
  end

  private

  def accumulate(totals, usage)
    totals[:prompt_tokens] += usage[:prompt_tokens]
    totals[:completion_tokens] += usage[:completion_tokens]
    totals[:total_tokens] += usage[:total_tokens]
    totals[:cost] += usage[:cost]
    totals
  end

  def empty_totals
    { calls: 0, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0, cost: 0.0 }
  end

  def cost_of(model, prompt_tokens, completion_tokens)
    self.class.cost_of(@prices, model, prompt_tokens, completion_tokens)
  end
end
