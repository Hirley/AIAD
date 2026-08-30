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

  # Só o que está sob o namespace `Aiad::` entra no pacote, mais licença e
  # README — e não `lib/` inteiro, que é o que a primeira versão deste arquivo
  # empacotava.
  #
  # O motivo não é tamanho, é colisão. Instalar uma gem põe o `require_paths`
  # dela no `$LOAD_PATH` de quem instalou, e as 57 classes deste projeto moram
  # soltas em `lib/`, sem namespace, com nomes genéricos: `tool.rb`,
  # `tracer.rb`, `stemmer.rb`, `tokenizer.rb`, `state_graph.rb`. Um
  # `require 'tool'` na aplicação de terceiro passaria a resolver para o nosso
  # arquivo, e a constante `Tool` no topo colidiria de vez. O `lib/aiad.rb` não
  # requer nenhuma delas de propósito, mas **não requerer não é não embarcar**:
  # quem entrega o arquivo no load path é o pacote, não o require.
  #
  # Então a gem carrega hoje o nome e a versão, e mais nada. Distribuir a
  # aplicação como biblioteca é uma decisão que vem **depois** de as classes
  # ganharem `Aiad::` (ou mudarem para `lib/aiad/`), não antes — e o serviço
  # HTTP, que é como o projeto é de fato rodado, continua saindo por Docker.
  spec.files         = `git ls-files -z lib/aiad.rb lib/aiad LICENSE README.md`.split("\x0")
  spec.require_paths = ['lib']

  # Sem dependência de runtime, porque não há runtime aqui: `logger`, `puma` e
  # `rack` são o que o **serviço** precisa, e o serviço não vai no pacote.
  # Declará-las assim mesmo arrastaria um servidor web inteiro para o bundle de
  # quem instalasse a gem, para carregar uma constante de versão. Elas voltam
  # no dia em que o código da aplicação voltar, junto.
end
