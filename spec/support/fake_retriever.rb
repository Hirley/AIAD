# frozen_string_literal: true

# Dublê de recuperação: devolve hits no mesmo formato do Qdrant e registra as
# chamadas, para verificar o que o RAG pediu (limite, filtro, coleção).
class FakeRetriever
  attr_reader :calls

  def initialize(results: [])
    @results = results
    @calls = []
  end

  def search(query, collection:, limit: 10, filter: nil, params: nil)
    @calls << { query: query, collection: collection, limit: limit, filter: filter, params: params }
    @results.first(limit)
  end
end
