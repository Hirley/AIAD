# frozen_string_literal: true

class FakeQdrantTransport
  attr_reader :requests

  def initialize(responses: {})
    @responses = responses
    @requests = []
  end

  def put(path, body)
    request(:put, path, body)
  end

  def post(path, body)
    request(:post, path, body)
  end

  def get(path)
    request(:get, path, nil)
  end

  def delete(path)
    request(:delete, path, nil)
  end

  def stub_response(path, response)
    @responses[path] = response
  end

  private

  def request(method, path, body)
    @requests << { method: method, path: path, body: body }
    @responses.fetch(path, { ok: true })
  end
end
