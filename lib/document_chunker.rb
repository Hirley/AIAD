# frozen_string_literal: true

class DocumentChunker
  def initialize(chunk_size:, overlap:)
    raise ArgumentError, 'chunk_size must be greater than overlap' if chunk_size <= overlap

    @chunk_size = chunk_size
    @overlap = overlap
  end

  def chunk(text)
    return [text] if text.length <= @chunk_size

    chunks = []
    step = @chunk_size - @overlap
    start = 0

    while start < text.length
      chunks << text[start, @chunk_size]
      start += step
    end

    chunks
  end
end
