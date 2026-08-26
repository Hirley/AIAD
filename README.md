# AIAD

[![CI](https://github.com/Hirley/AIAD/actions/workflows/ci.yml/badge.svg)](https://github.com/Hirley/AIAD/actions/workflows/ci.yml)

Assistente Inteligente de Análise de Documentos.

Veja a trilha de aprendizagem completa em [ROADMAP.md](ROADMAP.md) e o acompanhamento das tarefas no [board do projeto](https://github.com/users/Hirley/projects/4).

## Componentes

| Classe | Responsabilidade |
| --- | --- |
| `DocumentIngestor` | Ingestão e normalização do conteúdo bruto do documento |
| `ContentCleaner` | Limpeza por formato: texto, log (remove timestamp/nível) e PDF (marcadores de página, hifenização) |
| `DocumentChunker` | Divisão do conteúdo em chunks com sobreposição configurável |
| `EmbeddingGenerator` | Vetorização de texto (embeddings) e similaridade de cosseno |
| `QdrantClient` | CRUD de coleções e pontos no Qdrant, busca por similaridade com filtro de metadados e tuning de índice |
| `EtlPipeline` | Orquestra ingestão → limpeza → chunking → embeddings → indexação, e a busca semântica |
| `Bm25Index` | Índice léxico BM25 em memória (braço de palavra-chave da busca híbrida) |
| `HybridRetriever` | Funde o braço vetorial e o léxico por Reciprocal Rank Fusion |
| `MetadataFilter` | Avalia filtro de metadados no formato do Qdrant sobre um payload local |
| `PromptBuilder` | Monta o prompt do RAG com contexto numerado e origem de cada trecho |
| `RagPipeline` | Recuperação → prompt → geração, devolvendo resposta, trechos e origens |

### Injeção de dependência

O `QdrantClient` recebe o transporte HTTP por injeção de dependência (`QdrantClient.new(transport: ...)`),
o que permite testá-lo sem depender de um servidor Qdrant real. O transporte precisa responder a
`get(path)`, `put(path, body)`, `post(path, body)`, `patch(path, body)` e `delete(path)`, retornando um
Hash com a chave `:ok`.

O `EmbeddingGenerator` usa por padrão o *hashing trick* (determinístico, sem rede). Para usar um modelo real
basta injetar um provider: `EmbeddingGenerator.new(provider: ->(texto) { chamada_ao_modelo(texto) })`.

### Uso

```ruby
pipeline = EtlPipeline.new(qdrant: QdrantClient.new(transport: meu_transporte))

pipeline.run(conteudo, collection: 'documentos', source: 'relatorio.pdf', format: :pdf,
             metadata: { autor: 'joao' })

pipeline.search('quantos dias de férias por ano', collection: 'documentos', limit: 5,
                filter: { must: [{ key: 'autor', match: { value: 'joao' } }] })
```

Reprocessar a mesma origem gera os mesmos ids de ponto, então a reingestão atualiza os pontos em vez de duplicá-los.

### RAG

```ruby
rag = RagPipeline.new(retriever: pipeline, llm: meu_modelo, collection: 'documentos', top_k: 4)

resultado = rag.answer('quantos dias de férias por ano')
resultado[:answer]    # resposta gerada
resultado[:sources]   # origens que fundamentaram a resposta
resultado[:passages]  # trechos recuperados, com score
```

O modelo só precisa responder a `complete(prompt)`. Quando a recuperação não traz nada, o `RagPipeline`
responde que não sabe **sem chamar o modelo**, evitando gastar tokens numa pergunta sem contexto.

### Busca híbrida (vetorial + BM25)

```ruby
lexical = Bm25Index.new
pipeline = EtlPipeline.new(qdrant: qdrant, lexical_index: lexical)   # uma ingestão alimenta os dois índices

hibrido = HybridRetriever.new(vector_retriever: pipeline, lexical_index: lexical)
RagPipeline.new(retriever: hibrido, llm: meu_modelo, collection: 'documentos')
```

O `HybridRetriever` expõe a mesma interface de busca do `EtlPipeline`, então entra no lugar dele sem
nenhuma outra mudança. A fusão é por Reciprocal Rank Fusion (`1/(k + posição)`), que dispensa normalizar
escalas incomparáveis — similaridade de cosseno e score BM25 — e premia o que os dois braços concordam
em trazer para o topo. Cada resultado informa em `matched_by` qual braço o encontrou.

### Otimização da busca vetorial

```ruby
qdrant.create_collection('documentos', vector_size: 384,
                         hnsw: { m: 32, ef_construct: 200 },
                         quantization: { scalar: { type: 'int8', quantile: 0.99, always_ram: true } })

qdrant.update_collection('documentos', hnsw: { ef_construct: 256 })       # tuning sem recriar a coleção
qdrant.search('documentos', vector: vetor, params: { hnsw_ef: 128 })      # precisão x latência por consulta
```

## Setup

```bash
bundle install
```

## Testes

```bash
bundle exec rspec      # TDD - testes de unidade
bundle exec cucumber   # BDD - cenarios de aceitacao (Gherkin em pt)
bundle exec rubocop    # lint
```
