# frozen_string_literal: true

require_relative '../lib/content_cleaner'

RSpec.describe ContentCleaner do
  subject(:cleaner) { described_class.new }

  describe '#clean' do
    it 'raises for an unsupported format' do
      expect { cleaner.clean('conteudo', format: :planilha) }.to raise_error(ContentCleaner::UnsupportedFormatError)
    end

    context 'with plain text' do
      it 'collapses repeated whitespace and trims the lines' do
        raw = "  Relatório   anual  \n\n\n   de   vendas  "

        expect(cleaner.clean(raw, format: :texto)).to eq("Relatório anual\nde vendas")
      end
    end

    context 'with logs' do
      it 'removes timestamp and level prefixes, keeping only the messages' do
        raw = <<~LOG
          2026-08-26T10:00:00Z INFO  Iniciando processamento
          2026-08-26T10:00:01Z ERROR Falha ao conectar no banco

          2026-08-26T10:00:02Z WARN  Repetindo tentativa
        LOG

        expect(cleaner.clean(raw, format: :log)).to eq(
          "Iniciando processamento\nFalha ao conectar no banco\nRepetindo tentativa"
        )
      end

      it 'keeps lines that do not match the expected log prefix' do
        expect(cleaner.clean('stack trace sem prefixo', format: :log)).to eq('stack trace sem prefixo')
      end
    end

    context 'with text extracted from PDFs' do
      it 'rejoins words hyphenated across line breaks' do
        expect(cleaner.clean("docu-\nmento assinado", format: :pdf)).to eq('documento assinado')
      end

      it 'removes page markers and form feeds' do
        raw = "Primeira linha\nPágina 1 de 10\n\fSegunda linha"

        expect(cleaner.clean(raw, format: :pdf)).to eq("Primeira linha\nSegunda linha")
      end
    end
  end
end
