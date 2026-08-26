# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/qdrant_client'

RSpec.describe QdrantClient do
  let(:transport) { FakeQdrantTransport.new }

  subject(:client) { described_class.new(transport: transport) }

  describe '#create_collection' do
    it 'sends a PUT request with the vector configuration' do
      client.create_collection('documentos', vector_size: 384, distance: 'Cosine')

      expect(transport.requests.last).to eq(
        method: :put,
        path: '/collections/documentos',
        body: { vectors: { size: 384, distance: 'Cosine' } }
      )
    end

    it 'defaults distance to Cosine' do
      client.create_collection('documentos', vector_size: 384)

      expect(transport.requests.last[:body][:vectors][:distance]).to eq('Cosine')
    end

    it 'raises RequestError when the transport reports failure' do
      failing_transport = FakeQdrantTransport.new(responses: { '/collections/documentos' => { ok: false } })
      failing_client = described_class.new(transport: failing_transport)

      expect do
        failing_client.create_collection('documentos', vector_size: 384)
      end.to raise_error(QdrantClient::RequestError)
    end
  end

  describe '#upsert_points' do
    it 'sends the points to the collection points endpoint' do
      points = [{ id: 1, vector: [0.1, 0.2], payload: { chunk: 'a' } }]

      client.upsert_points('documentos', points)

      expect(transport.requests.last).to eq(
        method: :put,
        path: '/collections/documentos/points',
        body: { points: points }
      )
    end

    it 'raises RequestError when the transport reports failure' do
      failing_transport = FakeQdrantTransport.new(responses: { '/collections/documentos/points' => { ok: false } })
      failing_client = described_class.new(transport: failing_transport)

      expect do
        failing_client.upsert_points('documentos', [{ id: 1, vector: [0.1] }])
      end.to raise_error(QdrantClient::RequestError)
    end
  end

  describe '#search' do
    it 'sends a POST request with the query vector and returns the matches' do
      transport = FakeQdrantTransport.new(
        responses: {
          '/collections/documentos/points/search' => { ok: true, result: [{ id: 1, score: 0.9 }] }
        }
      )
      search_client = described_class.new(transport: transport)

      result = search_client.search('documentos', vector: [0.1, 0.2], limit: 5)

      expect(transport.requests.last).to eq(
        method: :post,
        path: '/collections/documentos/points/search',
        body: { vector: [0.1, 0.2], limit: 5 }
      )
      expect(result).to eq([{ id: 1, score: 0.9 }])
    end

    it 'defaults limit to 10' do
      client.search('documentos', vector: [0.1])

      expect(transport.requests.last[:body][:limit]).to eq(10)
    end

    it 'raises RequestError when the transport reports failure' do
      failing_transport = FakeQdrantTransport.new(
        responses: { '/collections/documentos/points/search' => { ok: false } }
      )
      failing_client = described_class.new(transport: failing_transport)

      expect do
        failing_client.search('documentos', vector: [0.1])
      end.to raise_error(QdrantClient::RequestError)
    end

    it 'includes a metadata filter in the request when given' do
      filter = { must: [{ key: 'autor', match: { value: 'joao' } }] }

      client.search('documentos', vector: [0.1], filter: filter)

      expect(transport.requests.last[:body][:filter]).to eq(filter)
    end

    it 'omits the filter key when none is given' do
      client.search('documentos', vector: [0.1])

      expect(transport.requests.last[:body]).not_to have_key(:filter)
    end
  end

  describe '#collection_exists?' do
    it 'returns true when Qdrant reports the collection exists' do
      transport = FakeQdrantTransport.new(
        responses: { '/collections/documentos/exists' => { ok: true, result: { exists: true } } }
      )

      expect(described_class.new(transport: transport).collection_exists?('documentos')).to be(true)
    end

    it 'returns false when Qdrant reports the collection does not exist' do
      transport = FakeQdrantTransport.new(
        responses: { '/collections/documentos/exists' => { ok: true, result: { exists: false } } }
      )

      expect(described_class.new(transport: transport).collection_exists?('documentos')).to be(false)
    end

    it 'sends a GET request to the exists endpoint' do
      client.collection_exists?('documentos')

      expect(transport.requests.last).to eq(
        method: :get,
        path: '/collections/documentos/exists',
        body: nil
      )
    end
  end

  describe '#delete_collection' do
    it 'sends a DELETE request to the collection endpoint' do
      client.delete_collection('documentos')

      expect(transport.requests.last).to eq(
        method: :delete,
        path: '/collections/documentos',
        body: nil
      )
    end

    it 'raises RequestError when the transport reports failure' do
      failing_transport = FakeQdrantTransport.new(responses: { '/collections/documentos' => { ok: false } })
      failing_client = described_class.new(transport: failing_transport)

      expect { failing_client.delete_collection('documentos') }.to raise_error(QdrantClient::RequestError)
    end
  end

  describe '#delete_points' do
    it 'sends the point ids to the points delete endpoint' do
      client.delete_points('documentos', [1, 2])

      expect(transport.requests.last).to eq(
        method: :post,
        path: '/collections/documentos/points/delete',
        body: { points: [1, 2] }
      )
    end

    it 'raises RequestError when the transport reports failure' do
      failing_transport = FakeQdrantTransport.new(
        responses: { '/collections/documentos/points/delete' => { ok: false } }
      )
      failing_client = described_class.new(transport: failing_transport)

      expect { failing_client.delete_points('documentos', [1]) }.to raise_error(QdrantClient::RequestError)
    end
  end

  describe '#count_points' do
    it 'returns the count reported by Qdrant' do
      transport = FakeQdrantTransport.new(
        responses: { '/collections/documentos/points/count' => { ok: true, result: { count: 42 } } }
      )

      expect(described_class.new(transport: transport).count_points('documentos')).to eq(42)
    end

    it 'includes a metadata filter in the request when given' do
      filter = { must: [{ key: 'autor', match: { value: 'joao' } }] }

      client.count_points('documentos', filter: filter)

      expect(transport.requests.last[:body][:filter]).to eq(filter)
    end

    it 'omits the filter key when none is given' do
      client.count_points('documentos')

      expect(transport.requests.last[:body]).not_to have_key(:filter)
    end
  end
end
