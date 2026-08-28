# frozen_string_literal: true

require_relative 'tool'

# Catálogo de ferramentas do agente: monta o texto que descreve as ferramentas
# no prompt e despacha a chamada que o modelo pediu.
#
# Decisão central: erro vira observação, não exceção. Ferramenta inexistente,
# argumento errado e falha dentro da ferramenta são coisas que acontecem o
# tempo todo quando quem escolhe é um modelo. Se qualquer uma delas derrubasse
# o laço, o agente perderia o trabalho já feito; devolvendo o erro como texto,
# ele lê o que houve e tenta outro caminho. Toda observação de erro começa com
# "Erro" para não se passar por resposta boa.
class ToolRegistry
  attr_reader :tools

  def initialize(tools = [])
    @tools = tools
    validate_unique_names!
  end

  def names
    @tools.map(&:name)
  end

  def fetch(name)
    @tools.find { |tool| tool.name == name.to_s }
  end

  def invoke(name, arguments = {})
    tool = fetch(name)
    return unknown(name) if tool.nil?

    tool.call(arguments).to_s
  rescue Tool::InvalidArgumentsError => e
    "Erro ao chamar #{name}: #{e.message}."
  rescue StandardError => e
    "Erro ao executar #{name}: #{e.message}."
  end

  def catalog
    return 'Nenhuma ferramenta disponível.' if @tools.empty?

    @tools.map { |tool| "- #{tool.signature}" }.join("\n")
  end

  private

  def unknown(name)
    "Erro: a ferramenta #{name} não existe. Disponíveis: #{names.join(', ')}."
  end

  def validate_unique_names!
    duplicated = names.tally.select { |_name, count| count > 1 }.keys
    return if duplicated.empty?

    raise ArgumentError, "ferramentas com nome repetido: #{duplicated.join(', ')}"
  end
end
