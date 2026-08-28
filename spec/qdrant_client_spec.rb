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
        body: { vector: [0.1, 0.2], limit: 5, with_payload: true }
      )
      expect(result).to eq([{ id: 1, score: 0.9 }])
    end

    # O padrão do Qdrant é não devolver o payload. Sem pedir, a busca traz id e
    # score sem texto nenhum, e o documento indexado some da resposta como se
    # não existisse — que é o pior tipo de falha: silenciosa e plausível.
    it 'asks for the payload, which is where the text and the source live' do
      client.search('documentos', vector: [0.1])

      expect(transport.requests.last[:body][:with_payload]).to be(true)
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

    it 'returns an empty list when the response carries no result' do
      expect(client.search('documentos', vector: [0.1])).to eq([])
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

  describe 'otimização da busca vetorial' do
    describe '#create_collection' do
      it 'sends the HNSW configuration when given' do
        client.create_collection('documentos', vector_size: 384, hnsw: { m: 32, ef_construct: 200 })

        expect(transport.requests.last[:body][:hnsw_config]).to eq(m: 32, ef_construct: 200)
      end

      it 'sends the quantization configuration when given' do
        quantization = { scalar: { type: 'int8', quantile: 0.99, always_ram: true } }

        client.create_collection('documentos', vector_size: 384, quantization: quantization)

        expect(transport.requests.last[:body][:quantization_config]).to eq(quantization)
      end

      it 'omits both configurations when they are not given' do
        client.create_collection('documentos', vector_size: 384)

        expect(transport.requests.last[:body].keys).to eq([:vectors])
      end
    end

    describe '#search' do
      it 'sends the search params when given' do
        client.search('documentos', vector: [0.1], params: { hnsw_ef: 128, exact: true })

        expect(transport.requests.last[:body][:params]).to eq(hnsw_ef: 128, exact: true)
      end

      it 'sends the quantization rescore option' do
        client.search('documentos', vector: [0.1], params: { quantization: { rescore: true } })

        expect(transport.requests.last[:body][:params]).to eq(quantization: { rescore: true })
      end

      it 'omits the params key when no tuning is requested' do
        client.search('documentos', vector: [0.1])

        expect(transport.requests.last[:body]).not_to have_key(:params)
      end

      it 'omits the params key when an empty hash is given' do
        client.search('documentos', vector: [0.1], params: {})

        expect(transport.requests.last[:body]).not_to have_key(:params)
      end
    end

    describe '#update_collection' do
      it 'sends a PATCH request with the new hnsw and optimizers configuration' do
        client.update_collection('documentos', hnsw: { ef_construct: 256 }, optimizers: { indexing_threshold: 20_000 })

        expect(transport.requests.last).to eq(
          method: :patch,
          path: '/collections/documentos',
          body: { hnsw_config: { ef_construct: 256 }, optimizers_config: { indexing_threshold: 20_000 } }
        )
      end

      it 'raises when nothing is given to update' do
        expect { client.update_collection('documentos') }.to raise_error(ArgumentError)
      end
    end
  end
end
