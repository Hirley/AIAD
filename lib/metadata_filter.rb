# frozen_string_literal: true

# Avalia um filtro de metadados no formato do Qdrant (`{ must: [...] }`) contra
# um payload local.
#
# O Qdrant aplica o filtro no servidor durante a busca vetorial; no braço léxico
# da busca híbrida o filtro precisa ser aplicado aqui, para que os dois braços
# enxerguem o mesmo recorte de documentos.
module MetadataFilter
  def self.matches?(payload, filter)
    return true if filter.nil?

    Array(filter[:must]).all? { |condition| condition_matches?(payload || {}, condition) }
  end

  def self.condition_matches?(payload, condition)
    return false unless payload.key?(condition[:key].to_sym)

    value = payload[condition[:key].to_sym]
    match = condition[:match] || {}

    return Array(match[:any]).map(&:to_s).include?(value.to_s) if match.key?(:any)

    value.to_s == match[:value].to_s
  end
  private_class_method :condition_matches?
end
