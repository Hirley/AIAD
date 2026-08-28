# frozen_string_literal: true

# Uma ferramenta que o agente pode acionar: nome, descrição, parâmetros e o
# código que executa de fato.
#
# A descrição não é enfeite — é o único texto que o modelo lê para decidir
# quando usar a ferramenta. Por isso é obrigatória.
#
# A validação de argumentos é estrita nos dois sentidos: falta de parâmetro
# declarado e parâmetro não declarado são erro. Modelo alucina nome de campo
# com facilidade, e aceitar em silêncio faria a ferramenta rodar com menos
# informação do que ela precisa. O erro é uma exceção específica justamente
# para o registro conseguir transformá-lo em observação e o agente se corrigir.
class Tool
  class InvalidArgumentsError < StandardError; end

  attr_reader :name, :description, :parameters

  def initialize(name:, description:, parameters: {}, handler: nil, &block)
    @name = name.to_s.strip
    @description = description.to_s.strip
    @parameters = parameters
    @handler = handler || block

    validate_declaration!
  end

  def call(arguments = {})
    symbolized = symbolize(arguments)
    validate_arguments!(symbolized)

    @handler.call(symbolized)
  end

  # Linha que entra no catálogo de ferramentas do prompt.
  def signature
    return "#{@name} — #{@description}" if @parameters.empty?

    "#{@name}(#{parameter_list}) — #{@description}"
  end

  private

  def parameter_list
    @parameters.map { |parameter, description| "#{parameter}: #{description}" }.join(', ')
  end

  def validate_declaration!
    raise ArgumentError, 'tool name cannot be blank' if @name.empty?
    raise ArgumentError, 'tool description cannot be blank' if @description.empty?
    raise ArgumentError, 'tool needs a handler' unless @handler.respond_to?(:call)
  end

  def validate_arguments!(arguments)
    missing = @parameters.keys.map(&:to_sym) - arguments.keys
    unexpected = arguments.keys - @parameters.keys.map(&:to_sym)

    raise InvalidArgumentsError, "faltam argumentos: #{missing.join(', ')}" if missing.any?
    raise InvalidArgumentsError, "argumentos desconhecidos: #{unexpected.join(', ')}" if unexpected.any?
  end

  def symbolize(arguments)
    arguments.to_h.transform_keys(&:to_sym)
  end
end
