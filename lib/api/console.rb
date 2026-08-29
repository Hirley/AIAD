# frozen_string_literal: true

module Api
  # Serve o console web em `GET /`: uma página só, que fala com a própria API
  # por `fetch`.
  #
  # Quatro decisões definem o comportamento:
  #
  # - **Middleware, e não rota da `App`.** Mesmo motivo do `MetricsEndpoint`: a
  #   `App` trata de documento, busca e pergunta, e responde JSON. Ensiná-la a
  #   devolver HTML misturaria duas coisas que mudam por razões diferentes.
  # - **Mesma origem, porque a alternativa era abrir CORS.** Uma página servida
  #   de outro lugar não conseguiria falar com esta API: o header
  #   `Authorization` dispara preflight, e liberar `Access-Control-Allow-Origin`
  #   seria afrouxar a API para ganhar conveniência de desenvolvimento. Servindo
  #   daqui, não existe requisição entre origens para autorizar.
  # - **Público por declaração, não por posição na pilha.** O console fica
  #   **dentro** da autenticação, e é o `AccessPolicy` que diz que `GET /` é
  #   público — do mesmo jeito que diz do `/health`. Pô-lo por fora do
  #   middleware também funcionaria, e é justamente o que não se quer: a regra
  #   da casa é que rota nova nasce protegida e só fica pública se alguém
  #   escrever isso no lugar onde se procura por essa informação.
  # - **A página não carrega chave nenhuma.** Ela pede a chave a quem abriu e a
  #   guarda só na aba. Embutir a chave no HTML servido publicaria, para quem
  #   abrisse a porta 9292, a credencial que a porta existe para exigir.
  class Console
    PATH = '/'
    CONTENT_TYPE = 'text/html; charset=utf-8'
    DEFAULT_PAGE = File.expand_path('../../public/index.html', __dir__)

    # A página é lida uma vez, na montagem. Se o arquivo não veio na imagem, o
    # processo morre no boot dizendo qual arquivo falta — que é melhor que
    # subir e devolver 404 na primeira visita, quando ninguém mais está olhando
    # o log de partida.
    def initialize(app, page: DEFAULT_PAGE)
      @app = app
      @body = File.read(page)
    end

    def call(env)
      return @app.call(env) unless console?(env)

      [200, { 'content-type' => CONTENT_TYPE }, [@body]]
    end

    private

    # Só o caminho exato, e só GET. Servir diretório exigiria resolver caminho
    # vindo do cliente, que é a porta de entrada clássica de travessia de
    # caminho — e para uma página só não há o que ganhar em troca.
    def console?(env)
      env['REQUEST_METHOD'] == 'GET' && env['PATH_INFO'] == PATH
    end
  end
end
