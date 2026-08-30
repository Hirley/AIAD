# frozen_string_literal: true

require_relative 'lib/aiad/version'

Gem::Specification.new do |spec|
  spec.name        = 'aiad'
  spec.version     = Aiad::VERSION
  spec.authors     = ['Hirley Esmeraldo Ribeiro']
  spec.email       = ['hirley@gmail.com']

  spec.summary     = 'Assistente Inteligente de Análise de Documentos.'
  spec.description = 'API de RAG sobre um acervo de documentos: recuperação híbrida, agentes, ' \
                     'avaliação de qualidade e observabilidade.'
  spec.homepage    = 'https://github.com/Hirley/AIAD'
  spec.license     = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['source_code_uri']       = spec.homepage
  spec.metadata['allowed_push_host']     = 'https://rubygems.pkg.github.com/Hirley'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files         = `git ls-files -z lib config.ru`.split("\x0")
  spec.require_paths = ['lib']

  spec.add_dependency 'logger'
  spec.add_dependency 'puma', '~> 6.4'
  spec.add_dependency 'rack', '~> 3.1'
end
