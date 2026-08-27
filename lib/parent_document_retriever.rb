# frozen_string_literal: true

require_relative 'parent_store'

# Parent Document Retriever: busca em chunks pequenos, que dão precisão, mas
# entrega ao modelo o documento inteiro, que dá contexto.
#
# Dois chunks do mesmo documento viram um resultado só, com o melhor score dos
# dois — senão o contexto do prompt seria o mesmo texto repetido.
class ParentDocumentRetriever
  POOL_FACTOR = 4

  def initialize(retriever:, store:, pool_factor: POOL_FACTOR)
    @retriever = retriever
    @store = store
    @pool_factor = pool_factor
  end

  def search(query, collection:, limit: 10, filter: nil, params: nil)
    children = @retriever.search(query, collection: collection, limit: limit * @pool_factor,
                                        filter: filter, params: params) || []

    collapse(children).first(limit)
  end

  private

  def collapse(children)
    children.each_with_object({}) do |child, parents|
      payload = child[:payload] || {}
      id = payload[:parent_id] || payload[:source] || child[:id]

      parents[id] = to_parent(child, payload, id) unless parents.key?(id)
    end.values
  end

  def to_parent(child, payload, id)
    text = @store.fetch(id) || payload[:text]

    child.merge(payload: payload.merge(text: text))
  end
end
