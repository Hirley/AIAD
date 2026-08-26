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
end
