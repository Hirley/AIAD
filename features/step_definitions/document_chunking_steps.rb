# frozen_string_literal: true

require_relative '../../lib/document_chunker'

Quando('eu divido o conteúdo em chunks de tamanho {int} com sobreposição de {int}') do |size, overlap|
  chunker = DocumentChunker.new(chunk_size: size, overlap: overlap)
  @chunks = chunker.chunk(@result)
end

Então('devo receber mais de um chunk') do
  expect(@chunks.size).to be > 1
end

Então('cada chunk deve ter no máximo {int} caracteres') do |max_size|
  expect(@chunks).to all(satisfy { |c| c.length <= max_size })
end

Então('devo receber exatamente {int} chunk') do |count|
  expect(@chunks.size).to eq(count)
end
