# frozen_string_literal: true

require_relative 'tool'

# A ferramenta que liga o agente ao acervo construído nas fases anteriores:
# o agente pede um termo, ela devolve os trechos recuperados.
#
# Devolve trecho, e não resposta pronta. Se a ferramenta já chamasse o RAG
# inteiro, gastaria uma chamada de modelo por consulta e o agente viraria só um
# invólucro; entregando o trecho cru, quem raciocina em cima é o agente.
#
# Cada trecho vem numerado e com a origem, para o agente conseguir citar de
# onde tirou a informação. Não achar nada é dito com todas as letras: devolver
# vazio convidaria o modelo a preencher a lacuna sozinho.
module RetrievalTool
  NAME = 'buscar_documentos'
  DESCRIPTION = 'Busca trechos nos documentos indexados. Use sempre que a resposta depender do acervo.'
  PARAMETERS = { termo: 'o assunto a procurar, em poucas palavras' }.freeze
  DEFAULT_TOP_K = 4
  NOTHING_FOUND = 'Nenhum trecho encontrado para esse termo. Tente outras palavras.'

  def self.build(retriever:, collection:, top_k: DEFAULT_TOP_K, name: NAME)
    Tool.new(name: name, description: DESCRIPTION, parameters: PARAMETERS) do |arguments|
      hits = retriever.search(arguments[:termo].to_s, collection: collection, limit: top_k) || []

      format_hits(hits)
    end
  end

  def self.format_hits(hits)
    excerpts = hits.filter_map { |hit| excerpt(hit) }
    return NOTHING_FOUND if excerpts.empty?

    excerpts.each_with_index.map { |text, index| "[#{index + 1}] #{text}" }.join("\n")
  end

  def self.excerpt(hit)
    payload = hit[:payload] || {}
    text = payload[:text].to_s
    return nil if text.empty?

    payload[:source] ? "#{payload[:source]}: #{text}" : text
  end
end
