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
| `HttpQdrantTransport` | Transporte HTTP real para o Qdrant, montado a partir do ambiente |
| `ExtractiveLlm` | Resposta extrativa, usada enquanto nenhum modelo real está configurado |
| `ApiKeyStore` | Chaves de API e escopos, guardadas como digest e comparadas em tempo constante |
| `Api::AccessPolicy` | Escopo exigido por rota; rota não mapeada exige o escopo mais restritivo |
| `Api::Authentication` | Middleware Rack de autenticação e autorização |
| `Api::App` | API HTTP: `/health`, `/documents`, `/search`, `/ask` |
| `Reranker` | Reordena os candidatos recuperados, com scorer injetável |
| `ParentDocumentRetriever` | Busca no chunk, entrega o documento inteiro |
| `ParentStore` | Guarda o documento inteiro de cada origem |
| `HydeRetriever` | Busca com uma resposta hipotética gerada pelo modelo |
| `TokenCounter` | Estimativa de tokens, com tokenizador injetável |
| `UsageMeter` | Acumula tokens e custo por modelo |
| `PromptCompressor` | Encaixa o contexto num orçamento de tokens |
| `SemanticCache` | Cache por similaridade de embedding |
| `CachedRag` | Decorador de cache na frente do RAG, um por filtro |
| `ModelRouter` | Roteia a pergunta entre modelo barato e modelo forte |
| `Tool` | Ferramenta do agente: nome, descrição, parâmetros e validação estrita dos argumentos |
| `ToolRegistry` | Catálogo de ferramentas do prompt e despacho da chamada, com erro virando observação |
| `RetrievalTool` | Liga o agente ao acervo: recebe um termo, devolve trechos com a origem |
| `ReactParser` | Leitura da saída do modelo no formato ReAct |
| `ReactAgent` | Laço ReAct: pensamento → ação → observação, com teto de iterações e trajeto registrado |
| `PlanParser` | Leitura do plano numerado que o modelo escreveu |
| `PlanAndSolveAgent` | Planeja antes de agir, executa passo a passo alimentando o seguinte e sintetiza a resposta |
| `SpecialistTool` | Embrulha um agente inteiro como ferramenta, para o time tratar especialista e ferramenta igual |
| `StateGraph` | Grafo de estado: nós que transformam o estado e arestas (fixas ou condicionais) que decidem o próximo |
| `AgentCrew` | Time multi-agente sobre o grafo: rotear → executar → revisar, com a revisão devolvendo o trabalho |
| `ConversationStore` | Guarda a conversa em memória, uma lista de turnos por id |
| `FileConversationStore` | Mesmo contrato, em disco: o histórico sobrevive ao processo |
| `ConversationMemory` | Turnos da conversa e o pedaço do histórico que cabe no orçamento de tokens |
| `ConversationalAgent` | Dá memória a qualquer agente: histórico junto da pergunta nova, resposta registrada |
| `Tracer` | Spans aninhados com duração, entrada, saída, tokens e erro; `Tracer.null` desliga tudo a custo zero |
| `SessionMetrics` | Latência, custo e tokens por sessão, com média, máximo e p95 |
| `MetricsExporter` | Liga o tracer ao `SessionMetrics`: o que já é instrumentado vira medição |
| `AnswerEvaluator` | Sustentação no contexto (alucinação) e relevância de resposta e de contexto, com juiz injetável |
| `EvaluationLog` | Média corrente das notas e a lista das respostas que pontuaram pior |
| `EvaluatedRag` | Decorador que pontua toda resposta assim que ela sai e alimenta o log |

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

### RAG avançado

| Recurso | Classe | Padrão na API |
| --- | --- | --- |
| Re-ranking | `Reranker` | ligado (`AIAD_RERANK`) |
| Busca híbrida | `HybridRetriever` | sempre |
| Parent Document Retriever | `ParentDocumentRetriever` | desligado (`AIAD_PARENT_DOCUMENTS`) |
| HyDE | `HydeRetriever` | desligado (`AIAD_HYDE`) |

Os três recuperadores têm a mesma interface de busca, então se empilham: híbrido por dentro, documento pai
por fora, HyDE por fora de tudo.

- **Re-ranking** reordena os candidatos olhando o texto inteiro. Com reranker o pipeline busca um pool
  maior que o `top_k` — reordenar só o que já cabia no contexto não mudaria nada. O scorer padrão mede
  cobertura léxica; para um cross-encoder de verdade, injete `Reranker.new(scorer: ...)`.
- **Parent Document Retriever** busca no chunk pequeno, que dá precisão, e entrega o documento inteiro,
  que dá contexto. Chunks do mesmo documento viram um resultado só, com o melhor score.
- **HyDE** pede ao modelo uma resposta hipotética e busca com ela, fechando o vão de vocabulário entre
  pergunta e documento. A pergunta original continua na consulta para não perder termo exato. Custa uma
  chamada a mais ao modelo por pergunta — por isso vem desligado.

### Controle de custos

| Recurso | Classe | Padrão na API |
| --- | --- | --- |
| Contagem de tokens | `TokenCounter`, `UsageMeter` | sempre |
| Compressão de contexto | `PromptCompressor` | `AIAD_CONTEXT_BUDGET` (1500) |
| Cache semântico | `SemanticCache`, `CachedRag` | ligado (`AIAD_CACHE`) |
| Roteamento de modelos | `ModelRouter` | disponível, não usado sem modelo real |

Toda resposta de `/ask` traz `usage` (tokens de prompt e de geração) e `cached`.

```json
{"answer": "...", "sources": ["politica.txt"], "cached": false,
 "usage": {"prompt_tokens": 96, "completion_tokens": 12, "total_tokens": 108}}
```

- **Contagem** é estimativa (`~4 caracteres por token`, com mínimo de um token por palavra). Para o número
  exato do provedor, injete o tokenizador dele em `TokenCounter.new(counter: ...)`. O `UsageMeter` acumula
  tokens e custo por modelo, a preço por milhão de tokens.
- **Compressão** normaliza espaço, descarta trecho repetido e, se ainda não couber, corta os menos
  relevantes — truncando o último em vez de devolver contexto vazio. O corte é medido palavra a palavra:
  cortar por número de caracteres não garantiria o orçamento.
- **Cache semântico** compara a pergunta por embedding, então pega reformulação, não só texto idêntico.
  Há **um cache por filtro de metadados**: a resposta restrita a um recorte não pode ser servida a quem
  perguntou sem o mesmo recorte. Resposta sem contexto não é cacheada — se o documento for indexado
  depois, a próxima pergunta precisa tentar de novo.
- **Roteamento** manda pergunta simples para o modelo barato e analítica para o forte, expondo
  `complete(prompt)` como qualquer modelo. Na dúvida escolhe o forte: errar para o lado caro custa
  dinheiro, para o lado barato custa uma resposta ruim.

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

## API HTTP

Suba tudo com Docker:

```bash
cp .env.example .env   # edite e troque as chaves antes de subir
docker compose up --build
```

A API sobe em `http://127.0.0.1:9292` e o Qdrant fica só na rede interna do compose — quem fala com o
mundo é a API, que exige chave.

| Rota | Escopo | O que faz |
| --- | --- | --- |
| `GET /health` | público | Verificação de saúde, não toca no Qdrant |
| `POST /documents` | `write` | Ingere um documento (`content`, `source`, `format`, `metadata`) |
| `POST /search` | `read` | Busca trechos (`query`, `limit`, `filter`) |
| `POST /ask` | `read` | Pergunta com RAG (`question`, `filter`) |

As classes de agente da Fase 3 — `ReactAgent`, `PlanAndSolveAgent`, `AgentCrew`, `ConversationalAgent` —
ainda **não têm rota**. Hoje elas são biblioteca, exercitada por RSpec e pelos cenários Cucumber, e o
`/ask` responde por RAG direto, sem agente e sem memória. Ligar o agente à API é o item 2 do projeto
integrador ([#5](https://github.com/Hirley/AIAD/issues/5)).

```bash
curl -X POST http://127.0.0.1:9292/documents \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"content":"A política de férias garante trinta dias por ano.","source":"politica.txt"}'

curl -X POST http://127.0.0.1:9292/ask \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"question":"quantos dias de férias por ano"}'
```

### Controle de acesso

Autenticação por chave de API no header `Authorization: Bearer <chave>`, com autorização por escopo:
`read` consulta, `write` ingere. As chaves são configuradas em `AIAD_API_KEYS`, no formato
`nome:chave:escopos`, separadas por `;`.

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'   # gere cada chave assim
```

Decisões que valem registrar:

- **A chave nunca é guardada em claro na memória do processo:** o `ApiKeyStore` guarda só o digest SHA-256
  e compara em tempo constante, para que uma chave errada não vaze pelo tempo da comparação. O `inspect`
  também é sobrescrito, para a chave não aparecer em log de exceção.
- **Rota nova nasce protegida:** a `AccessPolicy` exige o escopo mais restritivo para qualquer rota não
  mapeada, então esquecer de declarar uma rota falha fechando, não abrindo.
- **Erro não vaza detalhe interno:** chave recusada não volta ecoada no corpo, e falha do Qdrant vira
  `503` genérico em vez de `500` com o caminho interno que foi chamado.
- **O container não roda como root** e a imagem final não leva compilador nem as gems de teste.

O que **não** está implementado e um deploy real precisaria: rate limiting por chave, rotação/revogação de
chaves sem restart, TLS (hoje o TLS terminaria num proxy na frente) e auditoria de acesso.

### Modelo de linguagem

Sem modelo configurado, a API responde de forma **extrativa**: o `ExtractiveLlm` recorta o trecho mais
relevante do contexto e o devolve citado, sem gerar texto novo. É um substituto honesto para rodar a stack
inteira sem credencial de provedor — para respostas geradas, injete um modelo real no `RagPipeline`
(a interface é só `complete(prompt)`).

### Um limite importante do deploy atual

Boa parte do estado vive na memória do processo: o índice léxico `Bm25Index`, o `ParentStore` com os
documentos inteiros, o cache semântico que o `CachedRag` cria por filtro e — quando a memória de conversa
chegar à API — o `ConversationStore` padrão. Por isso o `config/puma.rb` fixa **um worker**: com mais de
um, cada worker teria a sua própria cópia e a resposta passaria a depender de qual deles atendeu a
requisição.

Os quatro não pesam igual. O BM25 é o grave, porque muda o resultado da busca híbrida em silêncio — para
escalar horizontalmente ele precisa virar índice compartilhado, ou dar lugar aos vetores esparsos do
próprio Qdrant. O cache e o `ParentStore` toleram uma cópia por worker, ao custo de mais chamadas ao
modelo e mais memória. E a conversa já tem a saída pronta ao lado: o `FileConversationStore` cumpre o
mesmo contrato e sobrevive ao processo.

## Testes

Com Ruby instalado na máquina:

```bash
bundle install
bundle exec rspec      # TDD - testes de unidade
bundle exec cucumber   # BDD - cenarios de aceitacao (Gherkin em pt)
bundle exec rubocop    # lint
```

Sem Ruby instalado, o compose tem um runner com as gems de teste. O código entra por bind mount, então
editar o arquivo e rodar de novo não exige rebuild:

```bash
docker compose run --rm test                          # rspec (comando padrão)
docker compose run --rm test bundle exec cucumber
docker compose run --rm test bundle exec rubocop
```

A suíte inteira, na mesma ordem do CI:

```bash
docker compose run --rm test bash -lc "bundle exec rubocop && bundle exec rspec && bundle exec cucumber"
```

O serviço fica atrás do profile `test`, então não sobe junto com a API. Depois de mexer no `Gemfile`,
refaça a imagem com `docker compose --profile test build test`.
