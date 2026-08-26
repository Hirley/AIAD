# frozen_string_literal: true

# Limpeza e estruturação de conteúdo não estruturado antes do chunking.
#
# Cada formato tem ruído próprio: logs trazem timestamp e nível em toda linha,
# texto extraído de PDF traz marcadores de página e palavras quebradas por hífen.
class ContentCleaner
  class UnsupportedFormatError < StandardError; end

  FORMATS = %i[texto log pdf].freeze

  LOG_PREFIX = %r{\A\[?\d[\d\-:.TZ+/ ]*\]?\s+(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s+(?:--\s*)?}
  PAGE_MARKER = /\A(?:página|page)\s+\d+(?:\s+(?:de|of)\s+\d+)?\z/i
  HYPHENATED_BREAK = /(\p{L})-\n(\p{L})/

  def clean(content, format: :texto)
    raise UnsupportedFormatError, "unsupported format: #{format}" unless FORMATS.include?(format)

    send("clean_#{format}", content.to_s)
  end

  private

  def clean_texto(content)
    join(content.lines.map { |line| line.gsub(/\s+/, ' ').strip })
  end

  def clean_log(content)
    join(content.lines.map { |line| line.strip.sub(LOG_PREFIX, '') })
  end

  def clean_pdf(content)
    rejoined = content.gsub(HYPHENATED_BREAK, '\1\2').delete("\f")
    lines = rejoined.lines.map { |line| line.gsub(/\s+/, ' ').strip }

    join(lines.grep_v(PAGE_MARKER))
  end

  def join(lines)
    lines.reject(&:empty?).join("\n")
  end
end
