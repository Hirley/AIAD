# frozen_string_literal: true

require_relative '../lib/etl_pipeline'

RSpec.describe EtlPipeline do
  let(:transport) { FakeQdrantTransport.new }
  let(:qdrant) { QdrantClient.new(transport: transport) }
  let(:embedder) { EmbeddingGenerator.new(dimensions: 16) }

  subject(:pipeline) do
    described_class.new(
      qdrant: qdrant,
      embedder: embedder,
      chunker: DocumentChunker.new(chunk_size: 20, overlap: 5)
    )
  end

  def upsert_request
    transport.requests.find { |request| request[:path] == '/collections/documentos/points' }
  end

  describe '#run' do
    it 'creates the collection with the embedder dimensions when it does not exist' do
      pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')

      create_request = transport.requests.find do |request|
        request[:method] == :put && request[:path] == '/collections/documentos'
      end

      expect(create_request[:body][:vectors][:size]).to eq(16)
    end

    it 'does not recreate a collection that already exists' do
      transport.stub_response('/collections/documentos/exists', { ok: true, result: { exists: true } })

      pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')

      create_requests = transport.requests.select do |request|
        request[:method] == :put && request[:path] == '/collections/documentos'
      end

      expect(create_requests).to be_empty
    end

    it 'sends one point per chunk, each with its embedding' do
      pipeline.run('a' * 45, collection: 'documentos', source: 'relatorio.txt')
      points = upsert_request[:body][:points]

      expect(points.size).to eq(3)
      expect(points.map { |point| point[:vector].size }).to all(eq(16))
    end

    it 'stores the source, format, chunk index and text in the payload' do
      pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')

      expect(upsert_request[:body][:points].first[:payload]).to include(
        source: 'relatorio.txt', format: :texto, chunk_index: 0
      )
    end

    it 'merges extra metadata into the payload' do
      pipeline.run('conteudo', collection: 'documentos', source: 'r.txt', metadata: { autor: 'joao' })

      expect(upsert_request[:body][:points].first[:payload][:autor]).to eq('joao')
    end

    it 'generates stable point ids so reprocessing the same source updates the points' do
      first = pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')
      second = pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')

      expect(first[:point_ids]).to eq(second[:point_ids])
    end

    it 'gives different ids to different sources' do
      first = pipeline.run('conteudo', collection: 'documentos', source: 'a.txt')
      second = pipeline.run('conteudo', collection: 'documentos', source: 'b.txt')

      expect(first[:point_ids]).not_to eq(second[:point_ids])
    end

    it 'cleans the content according to the given format' do
      pipeline.run("2026-08-26T10:00:00Z ERROR Falha\n", collection: 'documentos', source: 'app.log', format: :log)

      expect(upsert_request[:body][:points].first[:payload][:text]).to eq('Falha')
    end

    it 'returns a summary of the ingestion' do
      result = pipeline.run('conteudo do relatorio', collection: 'documentos', source: 'relatorio.txt')

      expect(result).to include(collection: 'documentos', source: 'relatorio.txt', format: :texto, chunks: 2)
    end

    it 'rejects blank content' do
      expect { pipeline.run('   ', collection: 'documentos', source: 'vazio.txt') }
        .to raise_error(DocumentIngestor::BlankContentError)
    end
  end

  describe 'indexação léxica para busca híbrida' do
    let(:lexical_index) { Bm25Index.new }

    subject(:pipeline) do
      described_class.new(
        qdrant: qdrant,
        embedder: embedder,
        chunker: DocumentChunker.new(chunk_size: 20, overlap: 5),
        lexical_index: lexical_index
      )
    end

    it 'indexes each chunk in the lexical index too' do
      pipeline.run('a' * 45, collection: 'documentos', source: 'relatorio.txt')

      expect(lexical_index.size).to eq(3)
    end

    it 'makes the chunk findable by its terms' do
      pipeline.run('erro ERR-4021', collection: 'documentos', source: 'incidente.txt')

      expect(lexical_index.search('ERR-4021').first[:payload][:source]).to eq('incidente.txt')
    end

    it 'uses the same point ids in both indexes' do
      result = pipeline.run('erro ERR-4021', collection: 'documentos', source: 'incidente.txt')

      expect(lexical_index.search('ERR-4021').first[:id]).to eq(result[:point_ids].first)
    end

    it 'works without a lexical index' do
      expect { described_class.new(qdrant: qdrant, embedder: embedder).run('texto', collection: 'c', source: 's') }
        .not_to raise_error
    end
  end

  describe '#search' do
    it 'embeds the query and returns the matches from Qdrant' do
      transport.stub_response(
        '/collections/documentos/points/search',
        { ok: true, result: [{ id: 1, score: 0.9 }] }
      )

      result = pipeline.search('relatorio', collection: 'documentos', limit: 3)

      expect(result).to eq([{ id: 1, score: 0.9 }])
      expect(transport.requests.last[:body][:vector].size).to eq(16)
      expect(transport.requests.last[:body][:limit]).to eq(3)
    end

    it 'forwards the metadata filter to Qdrant' do
      filter = { must: [{ key: 'source', match: { value: 'relatorio.txt' } }] }

      pipeline.search('relatorio', collection: 'documentos', filter: filter)

      expect(transport.requests.last[:body][:filter]).to eq(filter)
    end
  end

  describe 'armazenamento do documento pai' do
    let(:parent_store) { ParentStore.new }

    subject(:pipeline) do
      described_class.new(qdrant: qdrant, embedder: embedder, parent_store: parent_store,
                          chunker: DocumentChunker.new(chunk_size: 20, overlap: 5))
    end

    it 'stores the whole cleaned document, not the chunks' do
      pipeline.run('2026-08-26T10:00:00Z INFO  Linha de log', collection: 'documentos',
                                                              source: 'app.log', format: :log)

      expect(parent_store.fetch('app.log')).to eq('Linha de log')
    end

    it 'stamps the parent id on every chunk' do
      pipeline.run('a' * 45, collection: 'documentos', source: 'relatorio.txt')
      points = transport.requests.find { |request| request[:path] == '/collections/documentos/points' }[:body][:points]

      expect(points.map { |point| point[:payload][:parent_id] }).to all(eq('relatorio.txt'))
    end

    it 'works without a parent store' do
      expect { described_class.new(qdrant: qdrant, embedder: embedder).run('texto', collection: 'c', source: 's') }
        .not_to raise_error
    end
  end
end
