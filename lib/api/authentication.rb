# frozen_string_literal: true

require 'json'

require_relative '../api_key_store'
require_relative 'access_policy'

module Api
  # Middleware de controle de acesso: autentica a chave de API e verifica o
  # escopo exigido pela rota antes de deixar a requisição chegar na aplicação.
  #
  # 401 quando a credencial falta ou não confere; 403 quando a credencial é
  # válida mas não tem o escopo da rota. A chave recusada nunca é devolvida no
  # corpo da resposta, para não acabar em log de cliente ou de proxy.
  class Authentication
    BEARER = /\ABearer\s+(.+)\z/i
    PRINCIPAL_KEY = 'aiad.principal'

    def initialize(app, store: ApiKeyStore.from_env, policy: AccessPolicy)
      @app = app
      @store = store
      @policy = policy
    end

    def call(env)
      scope = @policy.scope_for(env['REQUEST_METHOD'], env['PATH_INFO'])
      return @app.call(env) if scope.nil?

      principal = @store.authenticate(token_from(env))
      return unauthorized if principal.nil?
      return forbidden(scope) unless principal[:scopes].include?(scope)

      env[PRINCIPAL_KEY] = principal
      @app.call(env)
    end

    private

    def token_from(env)
      match = BEARER.match(env['HTTP_AUTHORIZATION'].to_s)

      match && match[1].strip
    end

    def unauthorized
      error(401, 'credencial ausente ou inválida', 'www-authenticate' => 'Bearer realm="aiad"')
    end

    def forbidden(scope)
      error(403, "esta chave não tem o escopo #{scope}")
    end

    def error(status, message, headers = {})
      body = JSON.generate(error: message)

      [status, { 'content-type' => 'application/json' }.merge(headers), [body]]
    end
  end
end
