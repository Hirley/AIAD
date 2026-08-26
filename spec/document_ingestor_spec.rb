# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/document_ingestor'

RSpec.describe DocumentIngestor do
  subject(:ingestor) { described_class.new }

  it 'strips surrounding whitespace from the document content' do
    expect(ingestor.ingest('  relatório trimestral  ')).to eq('relatório trimestral')
  end

  it 'raises BlankContentError when the content is blank' do
    expect { ingestor.ingest('   ') }.to raise_error(DocumentIngestor::BlankContentError)
  end

  it 'raises BlankContentError when the content is nil' do
    expect { ingestor.ingest(nil) }.to raise_error(DocumentIngestor::BlankContentError)
  end
end
