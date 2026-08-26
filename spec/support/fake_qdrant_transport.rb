# frozen_string_literal: true

class FakeQdrantTransport
  attr_reader :requests

  def initialize(responses: {})
    @responses = responses
    @requests = []
  end

  def put(path, body)
    @requests << { path: path, body: body }
    @responses.fetch(path, { ok: true })
  end
end
