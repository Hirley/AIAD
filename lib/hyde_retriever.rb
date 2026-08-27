# frozen_string_literal: true

# HyDE (Hypothetical Document Embeddings): em vez de buscar com a pergunta,
# pede ao modelo uma resposta hipotética e busca com ela.
#
# A ideia é fechar o vão de vocabulário: pergunta e documento são escritos de
# jeitos diferentes, e o texto hipotético "parece" mais com o documento
# procurado do que a pergunta parece. A pergunta original continua na consulta
# para que termo exato — código, sigla, número — não se perca no caminho.
class HydeRetriever
  PROMPT = <<~TEXT
    Escreva um parágrafo curto que responderia à pergunta abaixo como se fosse
    trecho de um documento interno. Não diga que é hipotético.

    Pergunta: %<question>s
  TEXT

  def initialize(retriever:, llm:, prompt: PROMPT)
    @retriever = retriever
    @llm = llm
    @prompt = prompt
  end

  def search(query, collection:, limit: 10, filter: nil, params: nil)
    @retriever.search(expand(query), collection: collection, limit: limit, filter: filter, params: params)
  end

  private

  def expand(query)
    hypothesis = @llm.complete(format(@prompt, question: query)).to_s.strip
    return query if hypothesis.empty?

    "#{query}\n#{hypothesis}"
  end
end
