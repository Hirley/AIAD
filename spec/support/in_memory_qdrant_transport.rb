# frozen_string_literal: true

require_relative '../../lib/embedding_generator'

# Qdrant em memória: guarda os pontos indexados e responde à busca rankeando de
# verdade por similaridade de cosseno, com suporte a filtro de metadados.
#
# Diferente do FakeQdrantTransport (que devolve respostas fixas), este fake
# permite cenários de aceitação ponta a ponta — a recuperação do RAG é exercida
# de fato, sem subir um servidor.
class InMemoryQdrantTransport
  COLLECTION = %r{\A/collections/([^/]+)\z}
  POINTS = %r{\A/collections/([^/]+)/points\z}
  SEARCH = %r{\A/collections/([^/]+)/points/search\z}
  COUNT = %r{\A/collections/([^/]+)/points/count\z}
  DELETE_POINTS = %r{\A/collections/([^/]+)/points/delete\z}
  EXISTS = %r{\A/collections/([^/]+)/exists\z}

  OK = { ok: true }.freeze

  def initialize
    @collections = {}
  end

  def put(path, body)
    case path
    when COLLECTION then create_collection(Regexp.last_match(1))
    when POINTS then upsert(Regexp.last_match(1), body[:points])
    else OK
    end
  end

  def post(path, body)
    case path
    when SEARCH then { ok: true, result: search(Regexp.last_match(1), body) }
    when COUNT then { ok: true, result: { count: select(Regexp.last_match(1), body[:filter]).size } }
    when DELETE_POINTS then delete_points(Regexp.last_match(1), body[:points])
    else OK
    end
  end

  def get(path)
    return { ok: true, result: { exists: @collections.key?(Regexp.last_match(1)) } } if path.match(EXISTS)

    OK
  end

  def delete(path)
    @collections.delete(Regexp.last_match(1)) if path.match(COLLECTION)

    OK
  end

  def patch(_path, _body)
    OK
  end

  private

  def create_collection(name)
    @collections[name] ||= {}
    OK
  end

  def upsert(name, points)
    create_collection(name)
    points.each { |point| @collections[name][point[:id]] = point }
    OK
  end

  def delete_points(name, ids)
    ids.each { |id| @collections.fetch(name, {}).delete(id) }
    OK
  end

  def search(name, body)
    select(name, body[:filter])
      .map { |point| point.merge(score: EmbeddingGenerator.cosine_similarity(body[:vector], point[:vector])) }
      .sort_by { |point| -point[:score] }
      .first(body[:limit] || 10)
  end

  def select(name, filter)
    points = @collections.fetch(name, {}).values
    return points unless filter

    points.select { |point| matches?(point[:payload] || {}, filter) }
  end

  def matches?(payload, filter)
    Array(filter[:must]).all? do |condition|
      payload[condition[:key].to_sym].to_s == condition.dig(:match, :value).to_s
    end
  end
end
