# frozen_string_literal: true

class DocumentIngestor
  class BlankContentError < StandardError; end

  def ingest(text)
    raise BlankContentError, 'document content cannot be blank' if text.nil? || text.strip.empty?

    text.strip
  end
end
