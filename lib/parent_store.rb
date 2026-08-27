# frozen_string_literal: true

# Guarda o documento inteiro de cada origem, para que a recuperação possa
# devolver o pai do chunk que casou com a busca.
#
# Em memória, como o Bm25Index: serve para rodar e para teste; num deploy com
# vários processos precisa virar armazenamento compartilhado.
class ParentStore
  def initialize
    @documents = {}
  end

  def put(id, text)
    @documents[id] = text
    self
  end

  def fetch(id)
    @documents[id]
  end

  def size
    @documents.size
  end
end
