# frozen_string_literal: true

# Transporte que falha em toda requisição, para exercitar o caminho de erro:
# Qdrant fora do ar, rede caída, credencial recusada.
class FailingQdrantTransport
  def get(_path) = failure
  def delete(_path) = failure
  def put(_path, _body) = failure
  def post(_path, _body) = failure
  def patch(_path, _body) = failure

  private

  def failure
    { ok: false, error: 'conexão recusada' }
  end
end
