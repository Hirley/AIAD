# frozen_string_literal: true

require 'rack/test'
require 'tmpdir'

require_relative '../../lib/api/access_policy'
require_relative '../../lib/api/console'
require_relative '../../lib/content_cleaner'

RSpec.describe Api::Console do
  include Rack::Test::Methods

  let(:downstream) { ->(_env) { [200, { 'content-type' => 'application/json' }, ['{"api":true}']] } }

  around do |example|
    Dir.mktmpdir do |dir|
      @page = File.join(dir, 'index.html')
      File.write(@page, '<!doctype html><title>console</title>')
      example.run
    end
  end

  def app
    described_class.new(downstream, page: @page)
  end

  describe 'GET /' do
    it 'serves the page' do
      get '/'

      expect(last_response.body).to include('<title>console</title>')
    end

    it 'answers 200' do
      get '/'

      expect(last_response.status).to eq(200)
    end

    it 'announces HTML with the encoding, so the accents survive' do
      get '/'

      expect(last_response.headers['content-type']).to eq('text/html; charset=utf-8')
    end
  end

  # É middleware: tudo que não for a página tem de seguir para a API sem ser
  # tocado, ou a rota nova quebra as antigas.
  describe 'everything else' do
    it 'passes another path downstream' do
      get '/health'

      expect(last_response.body).to eq('{"api":true}')
    end

    it 'passes another method on the same path downstream' do
      post '/'

      expect(last_response.body).to eq('{"api":true}')
    end
  end

  # Falhar na montagem, e não na primeira visita: quem esquecer de copiar a
  # pasta para a imagem descobre no boot, com o caminho do arquivo na mensagem.
  describe 'when the page is missing' do
    it 'refuses to build' do
      expect { described_class.new(downstream, page: '/nao/existe/index.html') }
        .to raise_error(Errno::ENOENT)
    end
  end

  # A página é HTML solto, fora do alcance do Ruby e do Rubocop. Estes dois
  # exemplos são o que impede que ela envelheça em silêncio enquanto a API
  # muda debaixo dela.
  describe 'the page that actually ships' do
    let(:html) { File.read(described_class::DEFAULT_PAGE) }

    it 'offers exactly the formats the ingestion accepts' do
      oferecidos = html.scan(/<option value="([^"]+)"/).flatten

      expect(oferecidos).to match_array(ContentCleaner::FORMATS.map(&:to_s))
    end

    # Um `/aks` no lugar de `/ask` passaria por qualquer revisão e só apareceria
    # em produção, como 404 dentro de uma mensagem de erro.
    #
    # O exemplo de baixo sozinho passaria de graça se a expressão regular
    # deixasse de casar — lista vazia não tem rota desconhecida. Por isso o de
    # cima afirma **quais** rotas a página chama: ele é o que garante que o
    # outro está de fato olhando para alguma coisa.
    it 'calls the three API routes and the public health check' do
      expect(routes_called).to contain_exactly('/ask', '/search', '/documents', '/health')
    end

    it 'calls no route that the access policy does not know' do
      expect(routes_called - Api::AccessPolicy::RULES.keys.map(&:last)).to be_empty
    end

    def routes_called
      html.scan(%r{(?:chamar|fetch)\('(/[a-z]*)'}).flatten.uniq
    end
  end
end
