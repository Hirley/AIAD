# frozen_string_literal: true

require 'digest'
require 'openssl'

# Chaves de API e seus escopos, carregadas de configuração.
#
# Formato: `nome:chave:escopo1,escopo2;outro:chave2:escopo`.
#
# As chaves são guardadas apenas como digest SHA-256 e comparadas em tempo
# constante, para que uma chave inválida não vaze por quanto tempo a comparação
# leva. O inspect também é sobrescrito, para que a chave não apareça em log de
# erro ou em dump de exceção.
class ApiKeyStore
  class ConfigurationError < StandardError; end

  SCOPES = %i[read write].freeze
  ENV_VAR = 'AIAD_API_KEYS'

  def initialize(entries = {})
    @entries = entries
  end

  def self.from_env(env = ENV)
    parse(env[ENV_VAR])
  end

  def self.parse(configuration)
    entries = configuration.to_s.split(';').map(&:strip).reject(&:empty?).to_h do |entry|
      name, key, scopes = entry.split(':').map(&:to_s).map(&:strip)
      validate!(entry, name, key, scopes)

      [digest(key), { name: name, scopes: parse_scopes(entry, scopes) }]
    end

    new(entries)
  end

  def self.validate!(entry, name, key, scopes)
    return unless [name, key, scopes].any? { |part| part.nil? || part.empty? }

    raise ConfigurationError, "entrada de chave de API inválida: use nome:chave:escopos (recebido: #{entry.inspect})"
  end
  private_class_method :validate!

  def self.parse_scopes(entry, scopes)
    parsed = scopes.split(',').map(&:strip).reject(&:empty?).map(&:to_sym)
    unknown = parsed - SCOPES
    raise ConfigurationError, "escopo desconhecido em #{entry.inspect}: #{unknown.join(', ')}" if unknown.any?

    parsed
  end
  private_class_method :parse_scopes

  def self.digest(value)
    Digest::SHA256.digest(value.to_s)
  end

  def authenticate(token)
    return nil if token.nil? || token.empty?

    candidate = self.class.digest(token)
    _, principal = @entries.find { |stored, _| OpenSSL.fixed_length_secure_compare(stored, candidate) }

    principal
  end

  def names
    @entries.values.map { |principal| principal[:name] }
  end

  def empty?
    @entries.empty?
  end

  def inspect
    "#<#{self.class.name} principals=#{names.inspect}>"
  end
end
