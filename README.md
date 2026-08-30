# AIAD

[![CI](https://github.com/Hirley/AIAD/actions/workflows/ci.yml/badge.svg)](https://github.com/Hirley/AIAD/actions/workflows/ci.yml)

Assistente Inteligente de Análise de Documentos.

Veja a trilha de aprendizagem completa em [ROADMAP.md](ROADMAP.md) e o acompanhamento das tarefas no [board do projeto](https://github.com/users/Hirley/projects/4).

O nome `aiad` é publicado no GitHub Packages a cada tag de versão (`gem install aiad --source https://rubygems.pkg.github.com/Hirley`), mas o pacote carrega só o nome e a versão: as classes do projeto moram soltas em `lib/`, sem namespace, e embarcá-las poria `tool.rb`, `tracer.rb` e companhia no load path de quem instalasse. A aplicação continua sendo rodada por Docker — ver [Setup](#setup).

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
| `AnthropicLlm` | Modelo de verdade pela API de mensagens, com transporte injetável e chave fora do `inspect` |
| `ApiKeyStore` | Chaves de API e escopos, guardadas como digest e comparadas em tempo constante |
| `Api::AccessPolicy` | Escopo exigido por rota; rota não mapeada exige o escopo mais restritivo |
| `Api::Authentication` | Middleware Rack de autenticação e autorização |
| `Api::App` | API HTTP: `/health`, `/documents`, `/search`, `/ask`, `/agent` |
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
| `ConversationStore` | Guarda a conversa em memória, com teto de sessões e descarte da menos usada |
| `FileConversationStore` | Mesmo contrato, em disco: o histórico sobrevive ao processo |
| `ConversationMemory` | Turnos da conversa e o pedaço do histórico que cabe no orçamento de tokens |
| `ConversationalAgent` | Dá memória a qualquer agente: histórico junto da pergunta nova, resposta registrada |
| `Tracer` | Spans aninhados com duração, entrada, saída, tokens e erro; `Tracer.null` desliga tudo a custo zero |
| `SessionMetrics` | Latência, custo e tokens por sessão, com média, máximo e p95 |
| `MetricsExporter` | Liga o tracer ao `SessionMetrics`: o que já é instrumentado vira medição |
| `AnswerEvaluator` | Sustentação no contexto (alucinação) e relevância de resposta e de contexto, com juiz injetável |
| `LlmJudge` | Juiz de sustentação por modelo, injetável no `AnswerEvaluator`; entende sinônimo e paráfrase |
| `EvaluationLog` | Média corrente das notas e a lista das respostas que pontuaram pior |
| `EvaluatedRag` | Decorador que pontua toda resposta assim que ela sai e alimenta o log |
| `MetricRegistry` | Contadores, medidores e histogramas, com rótulo declarado e sob mutex |
| `PrometheusExposition` | Escreve o registro no formato de texto que o Prometheus raspa |
| `ProcessCollector` | Memória residente, CPU, threads e uptime, amostrados no momento do scrape |
| `Api::Instrumentation` | Middleware que conta e cronometra requisições, com a rota normalizada |
| `Api::MetricsEndpoint` | Serve `GET /metrics`, dentro do controle de acesso |
| `Api::RequestLogger` | Uma linha JSON por requisição, sem corpo e sem credencial |
| `Api::Observability` | Monta o registro de métricas e envolve a aplicação com log e instrumentação |
| `PrometheusTraceExporter` | Publica tokens, custo e latência de modelo no registro, span a span |
| `PrometheusEvaluationLog` | Publica as notas de avaliação no registro, sem levar o texto junto |
| `Stemmer` | Reduz a palavra ao radical em português, para "trabalhar" casar com "trabalho" |
| `RelevanceFloor` | Descarta o trecho que não tem a ver com a pergunta, para o assistente recusar em vez de errar com convicção |
| `LangfuseExporter` | Manda o trace para o Langfuse: autenticação, timeout e tratamento de erro |
| `LangfuseBatch` | Traduz o trace para os eventos da ingestão — a única parte não verificada contra o serviço real |
| `CompositeExporter` | Entrega o mesmo trace a vários destinos, sem que a queda de um corte os outros |

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

#### O índice léxico se reconstrói sozinho na partida

O `Bm25Index` vive em memória, então até há pouco todo restart da API apagava metade da busca híbrida. O
sintoma era o pior possível: a API subia saudável, respondia 200, e passava a buscar **só pelo vetor** —
com um embedder de hash no lugar de um modelo, isso é boa parte da qualidade indo embora sem nenhum
sinal. A única volta era reingerir os documentos na mão.

O texto de cada trecho já estava no payload do Qdrant desde a ingestão; ninguém o lia na partida. Agora o
`LexicalIndexLoader` varre a coleção página a página e reenche o índice, e o `Api::LexicalIndexWarmup`
decide o que fazer quando isso não dá certo:

- **Qdrant fora do ar não derruba a API.** Mesma inversão do exportador de trace e do avaliador — quem
  aquece não derruba quem faz, e as rotas já sabem responder 503 quando a busca falha.
- **Acervo maior que o teto também não derruba.** A varredura roda **antes de o Puma abrir a porta**, e
  sem teto o conserto teria trocado um defeito por outro pior: "sobe e busca pela metade" viraria "não
  sobe" num acervo grande, derrubando readiness probe e pondo o contêiner em loop de reinício. São dois
  tetos — `AIAD_LEXICAL_INDEX_MAX` (50 000 trechos) limita o trabalho, `AIAD_LEXICAL_INDEX_TIMEOUT` (30 s)
  limita a espera com um Qdrant lento. Estourando qualquer um, a API sobe com o índice parcial.
- **Mas nada disso é silencioso.** Dois medidores contam metade da história:
  `aiad_lexical_index_documents` diz quantos trechos entraram, e `aiad_lexical_index_complete` diz se isso
  é o acervo inteiro (`1`) ou só o que coube (`0`). O par é o que separa três situações que o número
  sozinho confunde: acervo vazio (`0` e `1`), acervo que não deu para ler (`0` e `0`) e acervo grande
  demais (`50000` e `0`).
- **A outra metade sai no log, porque ninguém olha painel durante um boot.** Quem sobe o contêiner e vê a
  API respondendo 200 lê log — e a métrica não tem como carregar o **motivo** sem virar um rótulo por
  situação. Sai uma linha por partida, no mesmo stream e no mesmo formato JSON do log de requisição:

  ```json
  {"ts":"2026-08-29T11:15:05Z","level":"warn","event":"lexical_index_warmup","documents":50000,"complete":false,"reason":"max_documents"}
  ```

  O `reason` distingue os três motivos de índice parcial — `max_documents`, `timeout` e `unreachable` — e
  continua na linha mesmo quando é nulo, para `jq` e Loki filtrarem por motivo sem tratar a chave ausente
  como um caso à parte.
- **Erro inesperado derruba a partida, e é de propósito.** Aqui houve um `rescue StandardError`, e ele
  engolia junto o que precisa ser barulhento: um `NoMethodError` no meio da varredura virava
  `documents 0` com `complete 0`, indistinguível de "o Qdrant não respondeu" — e o disfarce durava, porque
  a API responde 200 o tempo todo com a busca funcionando pela metade. Hoje só
  `QdrantClient::RequestError` degrada; o resto sobe e mata o boot com o stack trace na saída, que é a
  mesma escolha do console quando a página não veio na imagem: falhar na montagem, e não na primeira
  visita. Não há lista de erro de rede nesse `rescue` porque não chega nenhum — o `HttpQdrantTransport` já
  converte recusa de conexão, timeout e DNS em `{ ok: false }`, e o `QdrantClient` transforma isso em
  `RequestError`.

Reconstruir, e não persistir em disco: o acervo é a fonte, e um segundo lugar guardando a mesma verdade
divergiria no primeiro documento apagado direto no Qdrant.

O que isto **não** resolve, e vale saber antes de mexer no `workers` do Puma: o índice é uma estrutura na
memória do processo. Hoje há `workers 0` e `preload_app!`, então ele é montado uma vez e ponto. Com vários
workers o `preload_app!` faria o aquecimento rodar **uma vez só, no master**, e os workers herdariam o
índice pronto pelo fork — o custo de partida não se multiplicaria. O que se quebra não é a carga, é o que
vem depois: cada ingestão é atendida por um worker só, e a partir da primeira as cópias divergem em
silêncio. Para valer ali, o braço BM25 precisaria de um índice compartilhado ou dos vetores esparsos do
próprio Qdrant.

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

### Piso de relevância

Um recuperador devolve o top-k **por construção**, por pior que seja o melhor. Sem um piso, o pipeline
trata "o menos ruim" como "o certo": perguntado sobre um assunto que não está em documento nenhum, o
assistente responde com o que estiver mais perto, citando a origem, com toda a convicção de uma resposta
certa. Foi assim que o defeito apareceu — rodando a stack, não lendo o código.

```ruby
RagPipeline.new(retriever: retriever, llm: llm, collection: 'documentos',
                relevance_floor: RelevanceFloor.new)          # AIAD_RELEVANCE_FLOOR ajusta; 0 desliga
```

Abaixo do piso o pipeline cai no caminho que já existia para "não recuperei nada": responde *"Não
encontrei essa informação nos documentos indexados"*, não cita origem nenhuma e nem chama o modelo.

Decisões que valem registrar:

- **O piso não pode se apoiar no score da busca híbrida.** O RRF pontua por *posição* — `1/(k + posição)`
  —, não por qualidade. Medido na stack real, `politica-ferias.txt` tirou `0.03278688524590164` tanto
  para "quantos dias de férias por ano" quanto para "plano de saúde odontológico": o mesmo número até o
  último dígito. Qualquer limiar sobre esse score seria um limiar sobre nada. Por isso o piso mede outra
  coisa — quantos termos de conteúdo da pergunta aparecem no trecho.
- **Palavra funcional não conta**, e foi o que fez o piso funcionar. Medindo com "qual", "a", "de" na
  conta, pergunta respondível e pergunta sem resposta no acervo se sobrepunham em 0,50 e não havia
  limiar que as separasse. Tirando as funcionais, as respondíveis ficaram em 0,50–1,00 e as sem resposta
  em 0,00–0,33. A lista mora no `Tokenizer`, junto com o `AnswerEvaluator` que depende dela pelo mesmo
  motivo: duas listas divergiriam, e a divergência apareceria como nota que não bate com recusa.
- **0,45 é onde o erro custa menos, não a fronteira entre certo e errado.** Em catorze perguntas contra
  três documentos as respondíveis ficaram em 0,20–1,00 e as sem resposta em 0,00–0,33: **as faixas se
  sobrepõem**. Com onze perguntas parecia haver um vão limpo; duas perguntas a mais desfizeram a
  impressão. O número a observar é a taxa de recusa: subindo sem motivo, o piso está alto; pergunta sem
  resposta sendo respondida, está baixo.
- **Recusar não suja o painel de qualidade.** O `EvaluatedRag` já ignorava resposta sem contexto, então
  a recusa entra nesse caminho de graça — e a média de qualidade não desaba justamente quando o sistema
  passa a se comportar melhor.

**Limitação conhecida:** a cobertura é léxica, e uma pergunta pode ser respondida por um documento com
que ela quase não compartilha palavra. "posso pedir adiantamento antes de viajar" é respondível pela
política de reembolso e tira 0,20, porque só "adiantamento" aparece lá — a pergunta diz "viajar", o
documento diz "viagem". Isso fica **abaixo** de perguntas que o acervo não cobre, então nenhum valor de
piso resolve o caso. Resolveria um scorer que entendesse sinônimo e paráfrase — um cross-encoder ou um
LLM-as-judge —, e a injeção já está pronta para isso: `RelevanceFloor.new(scorer: ...)`.

### Stemming

O piso e o BM25 casam **radical**, não palavra. Antes disso, "quantos dias por semana posso trabalhar de
casa" era recusada mesmo com a política de trabalho remoto no acervo, porque a pergunta dizia
"trabalh**ar**" e o documento "trabalh**o**". Com o `Stemmer`, essa pergunta passou de 0,40 apontando
para o documento **errado** a 0,60 apontando para o **certo**.

**É um subconjunto reduzido do RSLP, não o RSLP inteiro.** O algoritmo original tem oito passos, algumas
centenas de regras e listas de exceção que só se acertam consultando a publicação; escrever isso de
memória seria escrever errado com aparência de certo — e stemmer errado não falha, ele conflacia em
silêncio e estraga o ranking. O que está aqui cobre plural, advérbio, as formas verbais comuns e a vogal
final. Trocar por uma implementação completa mexe num lugar só: quem chama depende de `Stemmer.stem`.

Decisões que valem registrar:

- **Não entra no caminho dos embeddings.** O `EmbeddingGenerator` projeta cada termo por hash, então
  stemizar ali mudaria todo vetor já gravado no Qdrant e exigiria reingestão do acervo. E há um motivo
  mais forte: o embedder de hash é substituto de um modelo de verdade, e modelo de verdade trata
  morfologia sozinho — receber texto pré-stemizado o deixaria pior. Já o índice BM25 é em memória e por
  processo, então mudar a tokenização dele não pede migração de nada.
- **`-am` e `-em` ficaram de fora das regras de verbo.** São terminações de terceira pessoa do plural,
  mas também o fim de muito substantivo comum — "viagem", "ordem", "imagem", "homem". Com a regra
  ligada, "viagem" virava "viag" e casava com qualquer verbo de mesmo radical. O RSLP resolve com lista
  de exceção; sem a lista, o certo é abrir mão da regra. O preço é "podem" não casar com "pode", e
  "viajar" não casar com "viagem" — que é justamente a limitação da seção anterior.
- **Piso de tamanho em toda regra.** Sem ele o stemmer come palavra curta inteira: "ar" viraria string
  vazia e casaria com tudo.

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
| `GET /` | público | Console web: ingerir, buscar e perguntar pelo navegador |
| `GET /health` | público | Verificação de saúde, não toca no Qdrant |
| `GET /metrics` | `metrics` | Métricas no formato de texto do Prometheus |
| `POST /documents` | `write` | Ingere um documento (`content`, `source`, `format`, `metadata`) |
| `POST /search` | `read` | Busca trechos (`query`, `limit`, `filter`) |
| `POST /ask` | `read` | Pergunta com RAG (`question`, `filter`) |
| `POST /agent` | `read` | Pergunta ao agente, que decide o que buscar (`question`, `session`) |

O `/ask` responde por RAG direto: uma recuperação, um prompt, uma resposta. O `/agent` põe um `ReactAgent`
na frente, com a busca como ferramenta e memória por sessão — ele decide **se** e **quantas vezes**
consultar o acervo antes de responder. Custa mais chamadas de modelo; serve para pergunta que uma
recuperação só não resolve.

O `PlanAndSolveAgent` e o `AgentCrew` continuam sem rota, como biblioteca exercitada por RSpec e Cucumber.

```bash
curl -X POST http://127.0.0.1:9292/documents \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"content":"A política de férias garante trinta dias por ano.","source":"politica.txt"}'

curl -X POST http://127.0.0.1:9292/ask \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"question":"quantos dias de férias por ano"}'
```

### Console web

`http://127.0.0.1:9292/` abre uma página com as três operações do dia a dia — ingerir, buscar e
perguntar — sem montar requisição na mão. A resposta vem com as origens citadas, os trechos recuperados e
o score de cada um, que é o que deixa ver a recuperação funcionando (ou não).

Três decisões, todas com uma alternativa que parecia mais fácil:

- **Servida pela própria API, mesma origem.** Não é preferência estética: não há CORS em lugar nenhum, e
  uma página servida de outro lugar não conseguiria falar com esta API — o header `Authorization` dispara
  preflight. Liberar `Access-Control-Allow-Origin` resolveria, e seria afrouxar a API para ganhar
  conveniência de desenvolvimento.
- **A página não carrega chave nenhuma, e também não guarda a que recebe.** Ela pede a chave a quem abriu
  e a mantém numa variável do próprio script: some no reload, e o campo se esvazia ao perder o foco.
  Embutir a chave no HTML servido publicaria, para quem abrisse a porta 9292, a credencial que a porta
  existe para exigir. Aqui esteve `sessionStorage`, e este README o descrevia como cuidado por ele sumir
  quando a aba fecha — a comparação certa não era com `localStorage`, era com memória pura:
  `sessionStorage` sobrevive ao reload e é legível por **qualquer** script desta origem, que é a mesma que
  serve o conteúdo dos documentos ingeridos. O preço do conserto é redigitar a chave a cada reload. Um
  cenário Cucumber cobra a propriedade: a página não chama armazenamento de navegador nenhum. O que estava
  lá antes — o corpo da resposta não conter as chaves configuradas — só falharia se alguém as escrevesse
  na página de propósito.
- **Pública por declaração, não por posição na pilha.** O `Api::Console` fica **dentro** da autenticação,
  e é o `AccessPolicy` que diz que `GET /` é público, do mesmo jeito que diz do `/health`. Pô-lo por fora
  do middleware também funcionaria — e furaria a regra da casa, que é rota nova nascer protegida e só
  ficar pública se alguém escrever isso onde se procura por essa informação.

A página é HTML solto, fora do alcance do Rubocop e do RSpec. Duas specs a seguram: os formatos do menu
de ingestão têm de bater com `ContentCleaner::FORMATS`, e toda rota que ela chama tem de existir no
`AccessPolicy` — um `/aks` no lugar de `/ask` passa por qualquer revisão e só aparece em uso.

O escopo da chave decide o que a página faz: `read` pergunta e busca, `write` também ingere. Com a chave
errada a API responde `esta chave não tem o escopo write`, e o console mostra essa frase em vez de
traduzir o status para uma mensagem genérica.

### A imagem

O `docker compose up` constrói o que precisa, mas a imagem final também se constrói sozinha — é o que um
registry ou um deploy fora do compose vai querer:

```bash
docker build -t aiad:latest .
```

O `runtime` é o último estágio do `Dockerfile` de propósito: `build: .` sem `target` pega sempre a imagem
final, nunca a de teste. O estágio `build` compila as gems nativas e fica para trás; o que atravessa é só
o bundle já compilado, sem `build-essential` e sem as gems de teste. Dá ~285 MB rodando como o usuário
`aiad`, não como root.

A imagem sozinha sobe e responde `200` em `/health`, `401` em qualquer rota sem chave — e `503` no `/ask`,
porque sem Qdrant na rede não há o que buscar. Para exercitar de verdade, é o compose.

### O agente e o modelo de verdade

Com `ANTHROPIC_API_KEY` no ambiente, a API passa a usar um modelo real — tanto no `/ask` quanto no
`/agent`. Sem ela, o `/ask` segue extrativo e o `/agent` responde `503` dizendo o que configurar.

```bash
ANTHROPIC_API_KEY=sua-chave
AIAD_MODEL=claude-sonnet-5          # opcional
```

```bash
curl -X POST http://127.0.0.1:9292/agent \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"question":"quantos dias de férias e como funciona o plano de saúde"}'
```

A resposta traz `answer`, `session`, `iterations`, `finished` e `tools`. A `session` volta sempre: mande-a
de novo na próxima pergunta e o agente continua de onde parou — é o que permite perguntar *"e quantos
períodos?"* sem repetir o assunto.

Decisões que valem registrar:

- **Sem modelo, o agente não existe — e a rota diz isso.** O `ExtractiveLlm` recorta trecho, não escreve
  "Pensamento / Ação / Resposta Final". Montar o ReAct em cima dele daria seis voltas no laço para
  devolver "não cheguei a uma conclusão": lento, caro e sem explicar. Um `503` imediato nomeando a
  variável que falta é uma falha melhor.
- **O trajeto não volta para o cliente.** As observações são trechos de documento que ninguém pediu —
  mesmo motivo pelo qual o `/ask` não devolve o prompt. Volta o que ajuda a confiar na resposta: quantas
  voltas deu, se concluiu e em que ferramentas se apoiou.
- **A sessão é criada quando não vem.** A primeira pergunta não precisa saber que existe sessão; a
  segunda já pode continuar.
- **O escopo é `read`.** O agente lê o mesmo acervo que o `/ask`, só que decidindo sozinho o que buscar.
  Não ingere nem apaga nada.
- **O modelo se identifica.** `AnthropicLlm` e `ExtractiveLlm` respondem a `model`, e o nome entra no
  trace: a métrica de custo distingue `model="extrativo"` de `model="claude-sonnet-5"`, que é a primeira
  coisa que se pergunta ao olhar uma conta.
- **A chave nunca aparece em `inspect`**, como no `ApiKeyStore`: um dump de exceção não pode carregar
  credencial.
- **Timeout explícito na chamada ao modelo.** Chamada sem timeout é a forma mais fácil de travar um
  processo web inteiro — as cinco threads do Puma ficariam presas esperando um servidor que não responde.

A memória da conversa é **por processo**, como o índice BM25, o `ParentStore` e o cache semântico: vale
para um worker, e com mais de um a conversa dependeria de qual deles atendeu.

Três tetos governam a conversa, e é fácil confundi-los:

| Teto | Mede | Padrão | Variável |
| --- | --- | --- | --- |
| Orçamento de histórico | **Custo de cada pergunta** — o histórico inteiro vai no prompt toda vez | 400 tokens | `AIAD_HISTORY_BUDGET` |
| Retenção de turnos | Memória de **uma** conversa | 100 turnos | — |
| Teto de conversas | Memória **do processo** | 500 sessões | `AIAD_MAX_SESSIONS` |

O orçamento é apertado e a retenção é folgada de propósito: o primeiro se paga em toda chamada, o segundo
só ocupa RAM. Passado o teto de conversas, sai a **menos recentemente usada** — e ler conta como uso, para
que uma conversa ativa não seja descartada como se estivesse parada.

Sem o teto de conversas, uma rota que cria uma sessão nova a cada pergunta sem `session` encheria o Hash
até o processo morrer. E o prompt continuaria correto o tempo todo, o que faria o problema não aparecer em
lugar nenhum até ser tarde demais.

O cliente do modelo é testado como o do Qdrant: transporte injetável, sem rede e sem credencial. A suíte
inteira continua rodando offline — o que não dá para verificar aqui é a resposta do provedor real, e por
isso o formato dela está isolado num único método.

### Controle de acesso

Autenticação por chave de API no header `Authorization: Bearer <chave>`, com autorização por escopo:
`read` consulta, `write` ingere, `metrics` raspa o `/metrics`. As chaves são configuradas em
`AIAD_API_KEYS`, no formato `nome:chave:escopos`, separadas por `;`.

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

### Métricas e log estruturado

A API expõe `GET /metrics` no formato de texto do Prometheus e escreve **uma linha JSON por requisição**
na saída padrão.

```bash
curl -H 'Authorization: Bearer SUA-CHAVE-DE-METRICAS' http://127.0.0.1:9292/metrics
```

| Métrica | Tipo | O que responde |
| --- | --- | --- |
| `aiad_http_requests_total` | contador | Throughput e taxa de erro, por método, rota e status |
| `aiad_http_request_duration_seconds` | histograma | Latência — o percentil se escolhe na hora de consultar |
| `aiad_http_requests_in_flight` | medidor | Quantas requisições estão sendo atendidas agora |
| `aiad_http_exceptions_total` | contador | Requisições que morreram sem devolver status |
| `aiad_process_resident_memory_bytes` | medidor | Memória residente |
| `aiad_process_cpu_seconds_total` | contador | CPU acumulada |
| `aiad_process_threads` | medidor | Threads vivas (o Puma atende com cinco) |
| `aiad_lexical_index_documents` | medidor | Trechos no índice BM25 — zero com acervo cheio é busca pela metade |
| `aiad_lexical_index_complete` | medidor | `1` se o índice cobre o acervo inteiro; `0` se parou no teto ou falhou |
| `aiad_process_uptime_seconds` | medidor | Tempo desde a subida |

Decisões que valem registrar:

- **`/metrics` tem escopo próprio, e não é público.** Rota, latência e status juntos são o mapa de como a
  aplicação é usada. Escopo separado de `read` porque o Prometheus não precisa ler documento nenhum, e
  quem lê documento não precisa ver a operação por dentro — menor privilégio nas duas direções.
- **A rota do rótulo é normalizada; o caminho cru nunca entra.** Um varredor pedindo mil caminhos
  inventados criaria mil séries temporais permanentes. Normalizado, ele cria uma, chamada `outra`.
  Cardinalidade de rótulo é a forma mais comum de derrubar um Prometheus, e vem de fora.
- **Histograma, não média.** Dez respostas de 1 s e uma de 30 s dão uma média tranquila e um usuário
  irritado. Com buckets, o p95 e o p99 se calculam na consulta.
- **Métrica e log ficam por fora da autenticação; o `/metrics`, por dentro.** Assim `401` e `403` entram
  na contagem — um pico deles é chave rotacionada sem avisar, ou alguém adivinhando credencial —, e a
  rota de métricas passa pelo mesmo controle de acesso que as outras.
- **Métrica sem rótulo nasce em zero.** "Zero" e "sem dados" se investigam de formas diferentes; só a
  série com rótulo não dá para inventar antes da primeira amostra.
- **Memória ausente é melhor que memória zerada.** Sem `/proc` para ler, a métrica não é declarada:
  publicar zero mostraria um processo leve e saudável exatamente onde não se sabe nada.

O log é uma linha JSON por requisição, com `ts`, `request_id`, `method`, `path`, `route`, `status`,
`duration_ms` e `principal` — pronto para Loki ou `jq`, sem regex. **Nunca** entram o corpo (que em
`/documents` é um documento inteiro e em `/ask` é a pergunta do usuário) nem a credencial: da chave vai só
o *nome* do principal. O `x-request-id` volta na resposta, e um id vindo do cliente é sanitizado antes de
ser escrito — uma quebra de linha nesse header viraria uma segunda linha de log inteiramente forjada.

Um `403` nomeia quem foi recusado: a credencial era válida, e "quem tentou o quê" é a pergunta que se faz
depois. Por isso a `Authentication` põe o principal no env **antes** de checar o escopo — o que não abre
nada, porque num `403` a requisição não chega na aplicação.

O que **não** está aqui e um deploy real precisaria: amostragem de log (hoje toda requisição vira uma
linha, o que numa carga alta é caro), retenção configurável e correlação automática entre o
`request_id` do log e o id do trace.

### Métricas de LLM

Além das de infraestrutura, o `/metrics` publica o que o modelo custou e o quanto se pode confiar na
resposta:

| Métrica | Tipo | O que responde |
| --- | --- | --- |
| `aiad_llm_calls_total` | contador | Quantas vezes o modelo foi acionado, por modelo |
| `aiad_llm_prompt_tokens_total` | contador | Tokens gastos em prompt |
| `aiad_llm_completion_tokens_total` | contador | Tokens gastos em resposta |
| `aiad_llm_cost_usd_total` | contador | Custo acumulado |
| `aiad_llm_latency_seconds` | histograma | Duração das chamadas ao modelo |
| `aiad_llm_groundedness` | histograma | Fração das frases sustentadas pelo contexto |
| `aiad_llm_answer_relevancy` | histograma | Quanto a resposta trata da pergunta feita |
| `aiad_llm_context_relevancy` | histograma | Sobreposição média entre a pergunta e os trechos recuperados |
| `aiad_llm_unsupported_sentences_total` | contador | Afirmações sem apoio que saíram para o usuário |

Decisões que valem registrar:

- **A latência medida é a do span que gastou token, não a da raiz.** A raiz inclui recuperação,
  compressão e montagem de prompt; chamar aquilo de "latência do modelo" seria culpar o modelo pelo tempo
  da busca. Comparar essa métrica com a latência do `/ask` no painel de infraestrutura é o que diz se o
  gargalo é o modelo ou a recuperação.
- **O critério é ter gasto token, não o nome do span.** Renomear um span não pode apagar a métrica. E
  como a varredura é na árvore inteira, um agente que chama o modelo cinco vezes rende cinco
  observações, não uma média achatada.
- **Pergunta sem contexto não é chamada de modelo.** O pipeline responde sem chamar o modelo; contar
  isso afundaria o custo médio por chamada e mentiria sobre quantas vezes o modelo foi acionado.
- **Cada nota tem a sua lista de baldes.** Era uma só para as três, com os cortes apertados perto de 1
  porque "a diferença entre 0,95 e 1,0 é a que importa". O problema não era o gosto, era a aritmética: as
  três notas são razões de inteiros pequenos — `k/n` com `n` = frases da resposta, `k/|Q|` com `|Q|` =
  termos de conteúdo da pergunta —, então para uma nota cair entre 0,9 e 1,0 é preciso denominador ≥ 11.
  As respostas daqui têm de uma a quatro frases, e aqueles cortes pediam resolução onde não existe valor
  nenhum. Hoje a sustentação corta em 0,0, para a corcova do "nada se sustentou" não dividir balde com
  "uma frase de quatro se sustentou" — são diagnósticos diferentes. E a relevância de contexto começa no
  próprio `RelevanceFloor::DEFAULT_MINIMUM`: nenhum trecho abaixo do piso chega à avaliação, então corte
  abaixo dele nasce morto, e amarrar a constante faz o histograma seguir o piso se ele mudar.
- **Pergunta e resposta nunca viram métrica.** Texto de usuário como rótulo é cardinalidade infinita — e
  o conteúdo acabaria guardado para sempre num sistema que ninguém trata como base de dados pessoais. O
  texto fica no log.
- **A avaliação fica por dentro do cache.** Resposta servida do cache já foi avaliada quando entrou;
  pontuá-la de novo contaria a mesma resposta duas vezes no histograma, inflando a média com repetição.
  Desligue com `AIAD_EVALUATE=0` se o custo de CPU por resposta incomodar.
- **Custo sai da mesma conta do `UsageMeter`.** Duas definições de "quanto custou" divergiriam na
  primeira mudança de tabela de preço. Sem preço configurado o custo é zero explícito — e o
  `ExtractiveLlm`, que é o padrão, realmente não custa nada.

Diferente do `SessionMetrics`, que guarda uma entrada por chamada e por sessão em memória, este caminho
tem memória fixa: um punhado de séries, não importa quantas perguntas cheguem. Quem guarda série temporal
é o Prometheus.

### O que as notas de qualidade não medem

As três notas saem de uma única medida: sobreposição de radicais entre dois textos. É barata, roda em
toda resposta sem rede e sem custo, e tem dois limites que já custaram caro uma vez. Ambos estão fixados
em spec — respectivamente em `spec/evaluation_independence_spec.rb` e no bloco
`the known limit of lexical grounding` de `spec/answer_evaluator_spec.rb`.

**A relevância de contexto não é independente do piso.** O `RelevanceFloor` decide o que entra no
contexto usando essa mesma sobreposição, e por um tempo a nota apenas confirmava a decisão dele: a versão
antiga contava os trechos com sobreposição *maior que zero*, e o piso só deixa passar trecho a partir de
0,45. O resultado era uma nota presa em 1,0 — cinco amostras na stack, cinco vezes 1,0; dezesseis mil
perguntas geradas, um único valor. Hoje a nota é a **média** da sobreposição, então piso mal calibrado
mantendo trecho a 0,45 aparece como 0,45 no painel. O parentesco entre as duas contas continua existindo;
o que se recuperou foi a capacidade de a nota dizer algo que o piso não disse.

**A sustentação não distingue paráfrase de alucinação.** Ela mede se a frase reaproveita o vocabulário do
trecho, não se a afirmação se apoia nele. Medido contra o acervo deste projeto, uma paráfrase correta
tirou 0,11 e uma alucinação pura tirou 0,17: as faixas **se sobrepõem**, e por isso mexer no
`SUPPORT_THRESHOLD` não resolve — afrouxar o corte aprova a alucinação antes de aprovar a paráfrase.

Hoje isso não dói porque o `ExtractiveLlm`, que é o padrão, recorta o trecho em vez de reescrevê-lo: a
resposta é substring literal do contexto e a nota é 1,0 por construção. **Dói ao plugar um modelo que
parafraseia**, e o sintoma é a sustentação desabando ao acusar de alucinação resposta correta.

A saída é o `judge:` do `AnswerEvaluator`, não um limiar novo, e já existe uma implementação pronta para
injetar: `LlmJudge` (`lib/llm_judge.rb`), que pergunta ao modelo se a afirmação se sustenta no contexto em
vez de medir vocabulário reaproveitado. `AIAD_ANSWER_JUDGE=llm` liga, e exige `ANTHROPIC_API_KEY` — sem
ela, a variável é ignorada e a heurística continua. **Não é o padrão**, de propósito: o `judge:` é chamado
uma vez por frase da resposta, não uma vez por resposta inteira, e isso não sobrevive ao primeiro pico de
tráfego. A heurística barata continua sendo o que roda em toda resposta sem custo; `LlmJudge` é para quem
aceita pagar por nota confiável em troca de menos throughput.

### A stack de observabilidade

Prometheus, Grafana, Loki e Promtail sobem juntos, atrás de um profile — não é preciso tê-los de pé para
trabalhar na API, e eles custam memória:

```bash
docker compose --profile observabilidade up -d
```

O Grafana fica em `http://127.0.0.1:3000` (usuário `admin`, senha em `GRAFANA_PASSWORD`), com dois
painéis já provisionados:

| Painel | Para quem olha |
| --- | --- |
| **AIAD — Infraestrutura e API** | Throughput, latência p95 e p99, memória, CPU, requisições em andamento, recusas de credencial e o log ao vivo |
| **AIAD — LLM: custo e qualidade** | Custo por pergunta, tokens por minuto, as três notas ao longo do tempo, o tamanho de cada corcova da sustentação, latência do modelo e frases sem apoio |

Decisões que valem registrar:

- **Um painel lê os baldes, e não só a média.** Os três histogramas de nota existiam desde o começo e
  nenhum painel os consultava — as três apareciam como `_sum/_count`, que é precisamente a média que o
  histograma foi criado para não ser. Noventa respostas perfeitas e dez inventadas dão 0,9, e 0,9 parece
  ótimo. O painel da sustentação lê `le="0"` e o topo da distribuição, e mostra o tamanho de cada
  corcova; a linha do "nada se sustentou" é a que se leva para uma conversa sobre risco.
- **Fontes de dados e painéis são provisionados por arquivo, não clicados na interface.** Painel que só
  existe no banco do Grafana morre com o volume, e ninguém consegue revisar num pull request o que foi
  configurado.
- **A chave do Prometheus não mora no `prometheus.yml`.** O arquivo é versionado, e chave em arquivo
  versionado é chave vazada. Ela chega por `AIAD_METRICS_TOKEN` e vira arquivo no boot, porque a
  configuração do Prometheus não expande variável de ambiente.
- **O Promtail descobre containers pelo socket do Docker**, e não por arquivo em
  `/var/lib/docker/containers`: no Docker Desktop esse diretório vive dentro da VM. É um privilégio
  grande — quem lê o socket do Docker manda no Docker — aceitável numa stack local e que num deploy real
  seria trocado por um agente sem esse acesso.
- **No Loki a disciplina de cardinalidade é a mesma.** Viram rótulo só `container`, `level` e `route`. O
  resto do JSON continua na linha, pesquisável, sem virar índice.
- **Só o Grafana publica porta.** Prometheus e Loki ficam na rede interna do compose, como o Qdrant.

### Rastreamento no Langfuse

O Prometheus responde *que* o custo subiu ontem às 3h. Ele não responde *por quê* — para isso é preciso a
requisição individual: qual pergunta chegou, qual prompt foi montado, o que o modelo devolveu, qual span
demorou. É o que vai para o Langfuse.

```bash
LANGFUSE_PUBLIC_KEY=pk-...
LANGFUSE_SECRET_KEY=sk-...
LANGFUSE_URL=https://cloud.langfuse.com   # ou a URL da sua instância
```

Sem o par de chaves o exportador não é montado, o trace vai só para o Prometheus e a API sobe igual:
observabilidade externa é opcional, não requisito de boot.

> **O formato do payload nunca foi verificado contra uma instância real.** Tudo o que o `LangfuseBatch`
> monta — nomes de campo, tipos de evento, a forma do lote — é o meu melhor entendimento da API de
> ingestão, escrito sem um servidor para confirmar. O Qdrant roda em container neste projeto e a API da
> Anthropic é exercitada de verdade quando há chave; o Langfuse, não. É por isso que a tradução mora
> numa classe separada do transporte: se o formato estiver errado, o conserto é em
> `lib/langfuse_batch.rb` e em nenhum outro lugar.

Decisões que valem registrar:

- **O trace é o contêiner, não uma observação.** A raiz vira as duas coisas. Sem a segunda, a duração da
  raiz não existiria em lugar nenhum e a cascata começaria no primeiro filho, como se o trabalho de fora
  fosse instantâneo.
- **Span com `usage` é geração; o resto é span.** É essa distinção que faz token e custo aparecerem no
  painel do Langfuse. O critério é o mesmo do `PrometheusTraceExporter` — duas definições de "isto foi
  uma chamada de modelo" divergiriam na primeira mudança, e aí os dois painéis contariam números
  diferentes para o mesmo dia.
- **Dois relógios, cada um no que sabe fazer.** O `Tracer` mede duração com relógio monotônico, que não
  anda para trás, e carimba o início com hora de parede uma vez só. O fim se calcula somando os dois. Ler
  o relógio de parede de novo no fim reintroduziria o salto de NTP que o monotônico existe para evitar —
  e sem o carimbo de parede não há como situar o span numa linha do tempo, porque valor monotônico só
  significa alguma coisa comparado consigo mesmo.
- **A queda do Langfuse não leva junto a métrica.** O `CompositeExporter` isola cada destino: um serviço
  externo fora do ar não pode apagar o número que se usa justamente para perceber isso. E a falha não
  some — ela sobe depois que todos foram servidos, e é o `Tracer` que decide não derrubar a requisição do
  usuário por causa do observador.

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
