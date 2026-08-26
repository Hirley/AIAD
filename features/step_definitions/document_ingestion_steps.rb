# frozen_string_literal: true

require_relative '../../lib/document_ingestor'

Dado('que eu tenho o conteúdo {string}') do |content|
  @content = content
end

Quando('eu envio o documento para ingestão') do
  @ingestor = DocumentIngestor.new
  begin
    @result = @ingestor.ingest(@content)
  rescue DocumentIngestor::BlankContentError => e
    @error = e
  end
end

Então('o conteúdo armazenado deve ser {string}') do |expected|
  expect(@result).to eq(expected)
end

Então('devo receber um erro de conteúdo em branco') do
  expect(@error).to be_a(DocumentIngestor::BlankContentError)
end
