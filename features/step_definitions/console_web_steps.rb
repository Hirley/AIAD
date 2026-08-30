# frozen_string_literal: true

require_relative '../../lib/api/console'

# Monta a pilha **com o console dentro da autenticação**, que é a composição
# que vai para produção. Os passos de `api_steps.rb` montam sem ele de
# propósito: lá o assunto é o controle de acesso, e um middleware a mais só
# tornaria a causa da falha menos óbvia.
Dado('que o console está no ar com as chaves:') do |table|
  configuration = table.hashes.map { |row| "#{row['nome']}:#{row['chave']}:#{row['escopos']}" }.join(';')

  lexical_index = Bm25Index.new
  etl = EtlPipeline.new(
    qdrant: QdrantClient.new(transport: InMemoryQdrantTransport.new),
    embedder: EmbeddingGenerator.new(dimensions: 64),
    lexical_index: lexical_index
  )
  rag = RagPipeline.new(
    retriever: HybridRetriever.new(vector_retriever: etl, lexical_index: lexical_index),
    llm: ExtractiveLlm.new, collection: API_COLLECTION, top_k: 2
  )

  @app = Api::Authentication.new(
    Api::Console.new(Api::App.new(etl: etl, rag: rag, collection: API_COLLECTION)),
    store: ApiKeyStore.parse(configuration)
  )
end

Então('a página servida deve ser HTML') do
  expect(last_response.headers['content-type']).to include('text/html')
  expect(last_response.body).to include('<!doctype html>')
end

# As quatro maneiras de uma página guardar texto onde outro script da mesma
# origem consegue lê-lo. A lista é do que **não** pode aparecer: a chave vive
# numa variável do script do console e em nenhum outro lugar.
ARMAZENAMENTO_DO_NAVEGADOR = %w[sessionStorage localStorage indexedDB document.cookie].freeze

# O que se cobra é o que a página **executa**. Um comentário que cita
# `sessionStorage` para contar por que ele saiu dali não é uso, e um teste que
# não distinguisse os dois estaria pedindo para o próximo comentário ser pior —
# a decisão some do lugar onde ela é lida, para o teste ficar quieto.
#
# `//` só conta como comentário no começo da linha: dentro de string ele é
# `http://`, e apagar até o fim da linha ali cortaria código de verdade.
def codigo_executavel(pagina)
  pagina.gsub(/<!--.*?-->/m, '').gsub(%r{/\*.*?\*/}m, '').gsub(%r{^\s*//.*$}, '')
end

Então('a página servida não deve usar armazenamento do navegador') do
  codigo = codigo_executavel(last_response.body)
  usados = ARMAZENAMENTO_DO_NAVEGADOR.select { |api| codigo.include?(api) }

  expect(usados).to be_empty, "a página servida chama #{usados.join(', ')}"
end

Então('a página servida deve ter um campo de senha para a chave') do
  expect(last_response.body).to include('type="password"')
end
