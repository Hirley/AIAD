# frozen_string_literal: true

require_relative '../lib/bm25_index'

RSpec.describe Bm25Index do
  subject(:index) { described_class.new }

  before do
    index.add(1, 'A política de férias garante trinta dias por ano', payload: { source: 'politica.txt' })
    index.add(2, 'O servidor de produção reinicia toda madrugada', payload: { source: 'servidor.txt' })
    index.add(3, 'O relatório de férias do time de produção', payload: { source: 'relatorio.txt' })
  end

  describe '#search' do
    it 'returns only the documents that contain a query term' do
      expect(index.search('férias').map { |hit| hit[:id] }).to contain_exactly(1, 3)
    end

    it 'returns the stored payload with each hit' do
      expect(index.search('servidor').first[:payload]).to eq(source: 'servidor.txt')
    end

    it 'ranks by relevance, giving more weight to rarer terms' do
      # "madrugada" aparece em um documento só; "de" aparece em todos.
      expect(index.search('de madrugada').first[:id]).to eq(2)
    end

    it 'ignores case and punctuation' do
      expect(index.search('FÉRIAS!').map { |hit| hit[:id] }).to contain_exactly(1, 3)
    end

    it 'returns an empty list when no document matches' do
      expect(index.search('criptomoeda')).to be_empty
    end

    it 'respects the limit' do
      expect(index.search('de', limit: 2).size).to eq(2)
    end

    it 'gives a positive score to every hit' do
      expect(index.search('férias').map { |hit| hit[:score] }).to all(be > 0)
    end

    it 'prefers the shorter document when both match equally' do
      short_index = described_class.new
      short_index.add(1, 'férias')
      short_index.add(2, 'férias e muitas outras palavras de enchimento no documento longo')

      expect(short_index.search('férias').first[:id]).to eq(1)
    end
  end

  describe '#size' do
    it 'reports how many documents are indexed' do
      expect(index.size).to eq(3)
    end

    it 'replaces a document indexed again with the same id' do
      index.add(1, 'conteúdo novo')

      expect(index.size).to eq(3)
      expect(index.search('férias').map { |hit| hit[:id] }).to contain_exactly(3)
    end
  end
end
