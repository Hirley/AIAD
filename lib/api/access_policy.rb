# frozen_string_literal: true

module Api
  # Escopo exigido por rota.
  #
  # O padrão para rota não mapeada é o escopo mais restritivo: um endpoint novo
  # nasce protegido, e só fica público se alguém disser aqui, explicitamente,
  # que ele é público.
  module AccessPolicy
    PUBLIC = nil
    MOST_RESTRICTIVE = :write

    RULES = {
      ['GET', '/health'] => PUBLIC,
      # /metrics tem escopo próprio, e não `read`: quem consulta documentos não
      # precisa ver latência, rota e status da operação, e o Prometheus não
      # precisa ler documento nenhum para raspar métrica. Menor privilégio nas
      # duas direções.
      ['GET', '/metrics'] => :metrics,
      ['POST', '/documents'] => :write,
      ['POST', '/search'] => :read,
      ['POST', '/ask'] => :read
    }.freeze

    def self.scope_for(method, path)
      key = [method.to_s.upcase, path.to_s]
      return RULES[key] if RULES.key?(key)

      MOST_RESTRICTIVE
    end
  end
end
