# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/document_chunker'

RSpec.describe DocumentChunker do
  subject(:chunker) { described_class.new(chunk_size: 10, overlap: 2) }

  it 'splits text into chunks no larger than chunk_size' do
    text = 'a b c d e f g h i j k l m n'
    chunks = chunker.chunk(text)

    expect(chunks).to all(satisfy { |c| c.length <= 10 })
  end

  it 'overlaps the tail of one chunk with the head of the next' do
    text = 'a b c d e f g h i j k l m n'
    chunks = chunker.chunk(text)

    expect(chunks.first[-2..]).to eq(chunks[1][0, 2])
  end

  it 'returns a single chunk when the text is smaller than chunk_size' do
    expect(chunker.chunk('short')).to eq(['short'])
  end

  it 'raises ArgumentError when chunk_size is not greater than overlap' do
    expect do
      described_class.new(chunk_size: 5, overlap: 5)
    end.to raise_error(ArgumentError, /chunk_size must be greater than overlap/)
  end
end
