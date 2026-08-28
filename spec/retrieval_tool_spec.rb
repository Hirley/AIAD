# frozen_string_literal: true

require_relative '../lib/retrieval_tool'

RSpec.describe RetrievalTool do
  let(:hits) do
    [
      { payload: { text: 'A política concede 30 dias de férias.', source: 'politica-rh.txt' }, score: 0.9 },
      { payload: { text: 'O pedido passa pelo gestor.', source: 'manual.txt' }, score: 0.7 }
    ]
  end

  let(:retriever) { FakeRetriever.new(results: hits) }

  subject(:tool) { described_class.build(retriever: retriever, collection: 'documentos') }

  it 'is a tool the agent can register' do
    expect(tool).to be_a(Tool)
  end

  it 'declares what it does, which is what the model reads to choose it' do
    expect(tool.description).not_to be_empty
  end

  describe 'the observation it returns' do
    it 'brings the retrieved text' do
      expect(tool.call(termo: 'férias')).to include('A política concede 30 dias de férias.')
    end

    # Sem a origem o agente responde sem ter como citar de onde tirou.
    it 'attributes each excerpt to its source' do
      expect(tool.call(termo: 'férias')).to include('politica-rh.txt').and include('manual.txt')
    end

    it 'numbers the excerpts so the agent can refer to them' do
      expect(tool.call(termo: 'férias')).to start_with('[1]')
    end

    # Devolver vazio faria o agente preencher a lacuna sozinho.
    it 'says plainly when it found nothing' do
      empty = described_class.build(retriever: FakeRetriever.new(results: []), collection: 'documentos')

      expect(empty.call(termo: 'jabuticaba')).to include('Nenhum trecho')
    end

    it 'ignores a hit with no text' do
      broken = described_class.build(retriever: FakeRetriever.new(results: [{ payload: {}, score: 0.5 }]),
                                     collection: 'documentos')

      expect(broken.call(termo: 'x')).to include('Nenhum trecho')
    end
  end

  describe 'the search it performs' do
    it 'searches the configured collection' do
      tool.call(termo: 'férias')

      expect(retriever.calls.first[:collection]).to eq('documentos')
    end

    it 'searches for the term the agent asked for' do
      tool.call(termo: 'férias')

      expect(retriever.calls.first[:query]).to eq('férias')
    end

    it 'limits how many excerpts come back, since each one costs tokens' do
      described_class.build(retriever: retriever, collection: 'documentos', top_k: 1).call(termo: 'férias')

      expect(retriever.calls.first[:limit]).to eq(1)
    end
  end
end
