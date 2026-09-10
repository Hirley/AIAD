# AIAD

[![CI](https://github.com/Hirley/AIAD/actions/workflows/ci.yml/badge.svg)](https://github.com/Hirley/AIAD/actions/workflows/ci.yml)

Assistente Inteligente de Análise de Documentos.

Veja a trilha de aprendizagem completa em [ROADMAP.md](ROADMAP.md) e o acompanhamento das tarefas no [board do projeto](https://github.com/users/Hirley/projects/4).

O nome `aiad` é publicado no GitHub Packages a cada tag de versão (`gem install aiad --source https://rubygems.pkg.github.com/Hirley`), mas o pacote carrega só o nome e a versão: as classes do projeto moram soltas em `lib/`, sem namespace, e embarcá-las poria `tool.rb`, `tracer.rb` e companhia no load path de quem instalasse. A aplicação continua sendo rodada por Docker — ver [Como rodar](#como-rodar).

## Objetivos e não-objetivos

Esta seção existe porque a falta dela já tinha consequência: sem escopo escrito, toda auto-revisão produzia
achado de superfície de produção para um app que não sai do laptop, e cada um parecia merecer prioridade. Uma
issue que só faz sentido sob um objetivo que o projeto não tem é ruído com aparência de dívida.

**O objetivo é aprender construindo, e deixar cada decisão legível.** A stack de RAG é escrita do zero — sem
framework de orquestração — para que cada peça possa ser explicada: os cabeçalhos de classe registram a decisão
tomada **e a alternativa rejeitada**, o comportamento entra por TDD/BDD, e o que pode falhar em silêncio ganha
log e métrica. A régua é "a decisão está explicada e medida", não "sobrevive a produção".

Os não-objetivos abaixo são decisões, não esquecimentos. Cada um já está encodado em alguma escolha do código; o
que faltava era dizê-lo em voz alta.

| Não-objetivo | Onde isso já está decidido |
| --- | --- |
| **Deploy público** | O compose publica **só em `127.0.0.1`** (API e Grafana), e a chave é digitada à mão no console. Não há modelo de ameaça com atacante anônimo na internet. |
| **Multi-tenant** | Uma coleção só, e os escopos são de **ação** (`read`, `write`, `metrics`), nunca de dono. Duas pessoas com a mesma chave veem o mesmo acervo, por construção. |
| **Ciclo de vida de credencial** | O `ApiKeyStore` guarda digest e compara em tempo constante: ele responde "esta chave vale?", e nunca "de quem é, quando expira, como se revoga". TLS, rotação e emissão ficam fora. |
| **Alta disponibilidade e vários workers** | Limite **aceito**, já documentado no `Api::LexicalIndexWarmup`: com `workers > 1` cada worker atende uma ingestão diferente e as cópias do índice BM25 divergem em silêncio. Resolver exige índice compartilhado ou vetores esparsos do Qdrant. Não é bug pendente. |
| **Acervo como dado sensível** | O acervo é tratado como **fixture**, não como base de dados real — ver a ressalva abaixo, que é a única desta lista que não era óbvia. |

### A ressalva sobre o acervo

Duas decisões do projeto parecem se contradizer, e vale dizer por que não se contradizem — **dada** a linha acima.

O `PrometheusEvaluationLog` recusa mandar pergunta e resposta para métrica, citando cardinalidade infinita e o
risco de o conteúdo ficar guardado para sempre num sistema que ninguém trata como base de dados pessoais. Já o
`LangfuseExporter`, com as duas chaves configuradas, manda para um serviço externo a pergunta, a resposta **e o
prompt** — e o prompt carrega os trechos recuperados do acervo.

As duas convivem porque o acervo aqui é material de teste: política de férias inventada, não prontuário. Métrica
e trace também têm naturezas diferentes — uma tem retenção indefinida e cardinalidade que explode, a outra é um
armazenamento feito para conteúdo e **opcional por configuração**.

O que muda se alguém apontar isto para documento real: o Langfuse deixa de ser um detalhe de configuração e
passa a ser uma decisão de tratamento de dados, e o console — que hoje não guarda nada além da chave em memória
— passa a precisar de um modelo de ameaça de verdade. Nesse dia, esta seção é o que deve ser reescrito primeiro.

### A regra que isto habilita

**Issue que só existe sob um não-objetivo fecha como `wontfix`, com link para esta seção** — em vez de ficar no
backlog dando a impressão de dívida.

Isso não torna sem valor toda proposta que encoste num não-objetivo. A [#25](https://github.com/Hirley/AIAD/issues/25)
é o exemplo: o argumento dela era defesa em profundidade contra um XSS que ninguém tem, mas metade do trabalho
era consertar documentação enganosa e um cenário de Cucumber que fingia testar segurança. Essa metade valia sob
qualquer escopo. O critério é o que sobra depois de tirar o que só o não-objetivo justificava.

## Como rodar

Não há Ruby na máquina: tudo passa por Docker.

```bash
cp .env.example .env    # troque as chaves antes de subir
docker compose up --build
```

A API sobe em `http://127.0.0.1:9292`; o Qdrant fica só na rede interna do compose. Quem fala com o
mundo é a API, e ela exige chave. Gere cada uma com:

```bash
docker compose run --rm test ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

Abrir `http://127.0.0.1:9292/` dá o console web: ingerir, buscar e perguntar pelo navegador, com as
origens citadas e o score de cada trecho recuperado. A chave é digitada ali e vive só na memória da
página — some no reload, de propósito.

A imagem final também se constrói sozinha, que é o que um registry vai querer: `docker build -t aiad .`
Dá ~285 MB, sem compilador e sem gems de teste, rodando como usuário não-root. Sozinha ela responde
`200` em `/health` e `503` no `/ask`, porque sem Qdrant não há o que buscar.

## API HTTP

| Rota | Escopo | O que faz |
| --- | --- | --- |
| `GET /` | público | Console web |
| `GET /health` | público | Verificação de saúde, não toca no Qdrant |
| `GET /metrics` | `metrics` | Métricas no formato de texto do Prometheus |
| `POST /documents` | `write` | Ingere um documento (`content`, `source`, `format`, `metadata`) |
| `POST /search` | `read` | Busca trechos (`query`, `limit`, `filter`) |
| `POST /ask` | `read` | Pergunta com RAG (`question`, `filter`) |
| `POST /agent` | `read` | Pergunta ao agente, que decide o que buscar (`question`, `session`) |

Autenticação por `Authorization: Bearer <chave>`, com escopo por rota: `read` consulta, `write` ingere,
`metrics` raspa o `/metrics`. Rota não mapeada exige o escopo mais restritivo — rota nova nasce
protegida.

```bash
curl -X POST http://127.0.0.1:9292/documents \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"content":"A política de férias garante trinta dias por ano.","source":"politica.txt"}'

curl -X POST http://127.0.0.1:9292/ask \
  -H 'Authorization: Bearer SUA-CHAVE' -H 'Content-Type: application/json' \
  -d '{"question":"quantos dias de férias por ano"}'
```

```json
{"answer": "...", "sources": ["politica.txt"], "cached": false,
 "usage": {"prompt_tokens": 96, "completion_tokens": 12, "total_tokens": 108, "measured": false}}
```

`measured` diz se os tokens vieram do provedor ou da estimativa do `TokenCounter`.

**`/ask` contra `/agent`.** O `/ask` faz RAG direto: uma recuperação, um prompt, uma resposta. O `/agent`
põe um `ReactAgent` na frente, com a busca como ferramenta e memória por sessão — ele decide **se** e
**quantas vezes** consultar o acervo. Custa mais chamadas de modelo, e serve para pergunta que uma
recuperação só não resolve. A resposta traz `answer`, `session`, `iterations`, `finished` e `tools`;
mande a `session` de volta na próxima pergunta e o agente continua de onde parou.

Sem `ANTHROPIC_API_KEY` o `/ask` responde de forma extrativa — recorta o trecho em vez de gerar texto — e
o `/agent` devolve `503` nomeando a variável que falta.

O `PlanAndSolveAgent` e o `AgentCrew` continuam sem rota, como biblioteca exercitada por RSpec e Cucumber.

## Configuração

Tudo por variável de ambiente, no `.env` ao lado do `docker-compose.yml`. O [`.env.example`](.env.example)
traz cada uma comentada; abaixo o que muda comportamento.

| Variável | Padrão | O que faz |
| --- | --- | --- |
| `AIAD_API_KEYS` | — (obrigatória) | `nome:chave:escopos`, separadas por `;` |
| `QDRANT_URL` | `http://qdrant:6333` | Onde está o Qdrant |
| `AIAD_COLLECTION` | `documentos` | Coleção usada pela API |
| `AIAD_TOP_K` | `4` | Trechos recuperados por pergunta |
| `AIAD_RELEVANCE_FLOOR` | `0.45` | Piso de relevância; `0` desliga e a API volta a responder pergunta que o acervo não cobre |
| `AIAD_RERANK` | ligado | Re-ranking dos candidatos |
| `AIAD_CACHE` | ligado | Cache semântico, um por filtro de metadados |
| `AIAD_HYDE` | desligado | Busca por resposta hipotética; custa uma chamada a mais por pergunta |
| `AIAD_PARENT_DOCUMENTS` | desligado | Busca no chunk, entrega o documento inteiro |
| `AIAD_CONTEXT_BUDGET` | `1500` | Orçamento de tokens do contexto |
| `AIAD_EVALUATE` | ligado | Avaliação contínua das respostas |
| `AIAD_LEXICAL_INDEX_MAX` | `50000` | Teto de trechos no aquecimento do índice léxico |
| `AIAD_LEXICAL_INDEX_TIMEOUT` | `30` | Teto de segundos do mesmo aquecimento |
| `ANTHROPIC_API_KEY` | — | Liga o modelo de verdade no `/ask` e no `/agent` |
| `AIAD_MODEL` | `claude-sonnet-5` | Qual modelo usar |
| `AIAD_MODEL_PRICES` | — | `modelo:entrada:saida` em dólares por milhão de tokens; sem isso o custo sai zero |
| `AIAD_ANSWER_JUDGE` | — | `llm` troca a heurística de sustentação pelo `LlmJudge`; exige `ANTHROPIC_API_KEY` |
| `AIAD_HISTORY_BUDGET` | `400` | Tokens de histórico que vão no prompt do agente a cada pergunta |
| `AIAD_MAX_SESSIONS` | `500` | Conversas guardadas em memória |
| `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY` / `LANGFUSE_URL` | — | Trace para o Langfuse; sem o par, o exportador não é montado |
| `AIAD_METRICS_TOKEN` / `GRAFANA_PASSWORD` | — | Profile `observabilidade` |

Três tetos governam a conversa do `/agent`, e é fácil confundi-los: o **orçamento de histórico** mede o
custo de cada pergunta (o histórico inteiro vai no prompt toda vez), a **retenção de turnos** (100, fixa)
mede a memória de uma conversa, e o **teto de conversas** mede a memória do processo. O primeiro é
apertado e o segundo folgado de propósito: um se paga em toda chamada, o outro só ocupa RAM.

## Observabilidade

`GET /metrics` no formato de texto do Prometheus, e **uma linha JSON por requisição** na saída padrão.

```bash
curl -H 'Authorization: Bearer SUA-CHAVE-DE-METRICAS' http://127.0.0.1:9292/metrics
```

| Métrica | Tipo | O que responde |
| --- | --- | --- |
| `aiad_http_requests_total` | contador | Throughput e taxa de erro, por método, rota e status |
| `aiad_http_request_duration_seconds` | histograma | Latência — o percentil se escolhe na consulta |
| `aiad_http_requests_in_flight` | medidor | Requisições sendo atendidas agora |
| `aiad_http_exceptions_total` | contador | Requisições que morreram sem devolver status |
| `aiad_process_resident_memory_bytes` | medidor | Memória residente |
| `aiad_process_cpu_seconds_total` | contador | CPU acumulada |
| `aiad_process_threads` | medidor | Threads vivas (o Puma atende com cinco) |
| `aiad_process_uptime_seconds` | medidor | Tempo desde a subida |
| `aiad_lexical_index_documents` | medidor | Trechos no índice BM25 — zero com acervo cheio é busca pela metade |
| `aiad_lexical_index_complete` | medidor | `1` se o índice cobre o acervo inteiro; `0` se parou no teto ou falhou |
| `aiad_llm_calls_total` | contador | Chamadas ao modelo, por modelo |
| `aiad_llm_prompt_tokens_total` / `aiad_llm_completion_tokens_total` | contador | Tokens gastos |
| `aiad_llm_cost_usd_total` | contador | Custo acumulado — zero sem `AIAD_MODEL_PRICES` |
| `aiad_llm_latency_seconds` | histograma | Duração das chamadas ao modelo |
| `aiad_llm_groundedness` | histograma | Fração das frases sustentadas pelo contexto |
| `aiad_llm_answer_relevancy` | histograma | Quanto a resposta trata da pergunta feita |
| `aiad_llm_context_relevancy` | histograma | Sobreposição média entre pergunta e trechos recuperados |
| `aiad_llm_unsupported_sentences_total` | contador | Afirmações sem apoio que saíram para o usuário |

O log traz `ts`, `request_id`, `method`, `path`, `route`, `status`, `duration_ms` e `principal` — pronto
para Loki ou `jq`, sem regex. **Nunca** entram o corpo (que em `/documents` é um documento inteiro e em
`/ask` é a pergunta do usuário) nem a credencial: da chave vai só o nome do principal. O `x-request-id`
volta na resposta. Além dele saem duas linhas de partida, `lexical_index_warmup` e `model_prices`, porque
ninguém olha painel durante um boot.

### A stack completa

Prometheus, Grafana, Loki e Promtail sobem juntos, atrás de um profile — não é preciso tê-los de pé para
trabalhar na API, e custam memória:

```bash
docker compose --profile observabilidade up -d
```

O Grafana fica em `http://127.0.0.1:3000` (`admin`, senha em `GRAFANA_PASSWORD`), com dois painéis
provisionados: **Infraestrutura e API** (throughput, latência, memória, CPU, recusas de credencial e o log
ao vivo) e **LLM: custo e qualidade** (custo por pergunta, tokens por minuto, as três notas ao longo do
tempo, o tamanho de cada corcova da sustentação e frases sem apoio).

Quatro decisões de infraestrutura, que não têm cabeçalho de classe onde morar:

- **Fontes de dados e painéis são provisionados por arquivo, não clicados na interface.** Painel que só
  existe no banco do Grafana morre com o volume, e ninguém revisa num pull request o que foi configurado.
- **A chave do Prometheus não mora no `prometheus.yml`.** O arquivo é versionado, e chave em arquivo
  versionado é chave vazada. Ela chega por `AIAD_METRICS_TOKEN` e vira arquivo no boot, porque a
  configuração do Prometheus não expande variável de ambiente.
- **O Promtail descobre containers pelo socket do Docker**, e não por arquivo em
  `/var/lib/docker/containers`: no Docker Desktop esse diretório vive dentro da VM. É um privilégio
  grande — quem lê o socket do Docker manda no Docker — aceitável numa stack local, e que num deploy real
  seria trocado por um agente sem esse acesso.
- **Só o Grafana publica porta.** Prometheus e Loki ficam na rede interna do compose, como o Qdrant. E no
  Loki a disciplina de cardinalidade é a mesma do Prometheus: viram rótulo só `container`, `level` e
  `route`; o resto do JSON continua na linha, pesquisável, sem virar índice.

### Langfuse

O Prometheus responde *que* o custo subiu ontem às 3h; não responde *por quê*. Para isso é preciso a
requisição individual — qual pergunta chegou, qual prompt foi montado, qual span demorou — e é o que vai
para o Langfuse, quando as duas chaves estão configuradas. Sem elas o exportador não é montado, o trace
vai só para o Prometheus e a API sobe igual.

> **O formato do payload nunca foi verificado contra uma instância real.** Tudo o que o `LangfuseBatch`
> monta — nomes de campo, tipos de evento, a forma do lote — é o melhor entendimento da API de ingestão,
> escrito sem um servidor para confirmar. O Qdrant roda em container neste projeto e a API da Anthropic é
> exercitada de verdade quando há chave; o Langfuse, não. Por isso a tradução mora numa classe separada do
> transporte: se o formato estiver errado, o conserto é em `lib/langfuse_batch.rb` e em nenhum outro lugar.

## Testes

Não há Ruby na máquina — a suíte roda pelo serviço `test` do compose, que fica atrás de um profile e não
sobe junto com a API. O código entra por bind mount, então editar e rodar de novo não exige rebuild:

```bash
docker compose run --rm test                          # rspec (comando padrão)
docker compose run --rm test bundle exec cucumber
docker compose run --rm test bundle exec rubocop
```

A suíte inteira, na mesma ordem do CI:

```bash
docker compose run --rm test bash -lc "bundle exec rubocop && bundle exec rspec && bundle exec cucumber"
```

Depois de mexer no `Gemfile`, refaça a imagem com `docker compose --profile test build test`.

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
| `ModelRouter` | Roteia a pergunta entre modelo barato e modelo forte — classe pronta e testada, **fora da pilha da API** ([#37](https://github.com/Hirley/AIAD/issues/37)) |
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

## Onde mora o porquê

Este README diz **o que existe e como usar**. A razão de cada decisão — com a alternativa que foi
rejeitada e o motivo — mora no cabeçalho da classe que a implementa, que é onde ela é lida por quem vai
mexer no código. Vinte e três classes carregam um cabeçalho desses; o `AnswerEvaluator` tem cinquenta
linhas de decisão numerada.

Isto aqui já foi uma segunda cópia dessas mesmas decisões, em prosa. Duas cópias de uma decisão divergem,
e nada testa prosa — a errada seria a que a pessoa lê primeiro.

| Para entender | Leia |
| --- | --- |
| Por que existe um piso de relevância, e por que 0,45 | `lib/relevance_floor.rb` |
| Por que a nota de sustentação não distingue paráfrase de alucinação | `lib/answer_evaluator.rb` |
| Por que o juiz por modelo não é o padrão | `lib/llm_judge.rb` |
| Por que os baldes de cada nota são diferentes | `lib/prometheus_evaluation_log.rb` |
| Por que o stemmer é um subconjunto do RSLP, e por que `-am`/`-em` ficaram de fora | `lib/stemmer.rb` |
| Por que a fusão é por Reciprocal Rank Fusion | `lib/hybrid_retriever.rb` |
| Por que o índice léxico se reconstrói na partida, e o que acontece com vários workers | `lib/api/lexical_index_warmup.rb` |
| Por que a varredura pagina e tem dois tetos | `lib/lexical_index_loader.rb` |
| Por que o preço vem do ambiente e não há tabela embutida | `lib/usage_meter.rb` |
| Por que o uso medido volta junto com o texto, e nunca no objeto | `lib/anthropic_llm.rb` |
| Por que a chave vira digest e a comparação é em tempo constante | `lib/api_key_store.rb` |
| Por que o console é servido pela própria API, e não guarda a chave | `lib/api/console.rb`, `public/index.html` |
| Por que o cache fica por fora da avaliação | `lib/cached_rag.rb`, `lib/evaluated_rag.rb` |
| Por que a queda do Langfuse não leva a métrica junto | `lib/composite_exporter.rb` |
| Por que a rota do rótulo é normalizada antes de virar métrica | `lib/api/instrumentation.rb` |
| Por que o log não leva corpo nem credencial | `lib/api/request_logger.rb` |
| Como o transporte e o modelo entram por injeção de dependência | `lib/qdrant_client.rb`, `lib/embedding_generator.rb` |

Como trabalhar neste repositório — TDD/BDD, lint, convenção de commit, o que o CI cobre — está no
[CLAUDE.md](CLAUDE.md). A trilha de aprendizagem, fase a fase, está na [ROADMAP.md](ROADMAP.md).
