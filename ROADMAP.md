# Trilha de Aprendizagem — Engenharia de IA Aplicada (AIAD)

Trilha em quatro fases incrementais, do nível fundamental à produção e observabilidade avançada.
Acompanhamento das tarefas no board: https://github.com/users/Hirley/projects/4

## Setup do Projeto (TDD/BDD) — App base em Ruby
**Foco:** preparar o esqueleto do projeto seguindo TDD (unidade) e BDD (comportamento/aceitação), antes de incorporar o restante da trilha.

- **Setup:** rbenv/rvm (`.ruby-version`), Bundler (`Gemfile`), estrutura `app/`, `lib/`, `spec/`, `features/`.
- **TDD — RSpec:** ciclo Red → Green → Refactor. Unidades: `DocumentIngestor` (ingestão/normalização), `ContentCleaner` (limpeza por formato), `DocumentChunker` (chunking com overlap), `EmbeddingGenerator` (vetorização), `QdrantClient` (coleções, pontos e busca, com transporte injetável para testes sem servidor real) e `EtlPipeline` (orquestração).
- **BDD — Cucumber/Gherkin (pt):** cenários de aceitação em `features/document_ingestion.feature`, `features/document_chunking.feature`, `features/qdrant_client.feature` e `features/etl_pipeline.feature`, com os respectivos step definitions.
- **Qualidade/CI:** Rubocop (`.rubocop.yml`) e pipeline no GitHub Actions (`.github/workflows/ci.yml`) rodando `rubocop`, `rspec` e `cucumber` a cada push/PR.

> Issue: [#6](https://github.com/Hirley/AIAD/issues/6) — **concluída**
>
> Os itens acima nomeiam os arquivos que existem: o esqueleto saiu como planejado, e é a base sobre a qual as quatro fases foram construídas.

## Fase 1: Fundamentos de Engenharia de Dados & Bancos Vetoriais
**Foco:** Construção e preparação do pipeline de entrada (ETL) e armazenamento para IA.

- Pipelines de ETL: processamento, limpeza e estruturação de dados não estruturados (PDFs, textos, logs).
- Bancos Vetoriais (Qdrant):
  - Conceitos de embeddings (vetorização de texto).
  - Indexação, distância vetorial (Cosine, Euclidean, Dot Product) e filtros de metadados.
  - Operações de CRUD de coleções e otimização de busca vetorial no Qdrant.

> Issue: [#1](https://github.com/Hirley/AIAD/issues/1) — **concluída**
>
> Entregue via TDD/BDD, tudo testável sem servidor Qdrant nem chamada a modelo externo:
>
> - **ETL (`lib/etl_pipeline.rb`, `lib/content_cleaner.rb`):** ingestão → limpeza por formato (texto, log, PDF) → chunking com overlap → embeddings → indexação. Payload guarda origem, formato, índice do chunk e texto; os ids são determinísticos, então reprocessar a mesma origem atualiza os pontos em vez de duplicá-los.
> - **Embeddings (`lib/embedding_generator.rb`):** vetorização por *hashing trick* (determinística, sem rede), vetores normalizados, similaridade de cosseno e provider injetável para modelos reais.
> - **Qdrant — coleções (`lib/qdrant_client.rb`):** `create_collection` (com `distance` configurável), `collection_exists?`, `delete_collection`, `update_collection`.
> - **Qdrant — pontos:** `upsert_points`, `delete_points`, `count_points`.
> - **Qdrant — busca:** `search` por similaridade, com `limit` e filtro de metadados opcional.
> - **Otimização:** `hnsw` (`m`, `ef_construct`) e `quantization` na criação, tuning por `update_collection` e ajuste de precisão por consulta via `params: { hnsw_ef:, exact:, quantization: }`.

## Fase 2: Arquiteturas de RAG & Otimização de Tokens
**Foco:** Recuperação contextual eficiente e redução de custos.

- Retrieval-Augmented Generation (RAG):
  - RAG Básico (Chunking, Retrieval, Generation).
  - RAG Avançado: Hybrid Search (Busca Vetorial + BM25), Re-ranking, Parent Document Retriever e HyDE.
- Otimização de Custos e Performance:
  - Gestão e contagem de tokens em tempo real.
  - Técnicas de Prompt Compression e uso de Caching (ex: Semantic Cache).
  - Seleção dinâmica de modelos (Model Routing) com base em complexidade.

> Issue: [#2](https://github.com/Hirley/AIAD/issues/2) — **concluída**
>
> - **RAG básico** (`lib/rag_pipeline.rb`, `lib/prompt_builder.rb`): recuperação dos top-k trechos, prompt com contexto numerado e origem de cada trecho, geração com modelo injetável. Sem contexto recuperado, responde que não sabe sem chamar o modelo.
> - **Hybrid Search** (`lib/hybrid_retriever.rb`, `lib/bm25_index.rb`): braço vetorial + braço léxico BM25 fundidos por Reciprocal Rank Fusion, com o filtro de metadados valendo para os dois braços. A mesma ingestão alimenta os dois índices.
> - **Re-ranking** (`lib/reranker.rb`): reordena o pool recuperado olhando o texto inteiro; scorer injetável para cross-encoder.
> - **Parent Document Retriever** (`lib/parent_document_retriever.rb`): busca no chunk pequeno e entrega o documento inteiro, colapsando chunks do mesmo documento.
> - **HyDE** (`lib/hyde_retriever.rb`): gera uma resposta hipotética e busca com ela, mantendo a pergunta original na consulta.
> - **Tokens** (`lib/token_counter.rb`, `lib/usage_meter.rb`): estimativa por resposta e acumulado de tokens e custo por modelo.
> - **Prompt compression** (`lib/prompt_compressor.rb`): normaliza, deduplica e corta o contexto até caber no orçamento.
> - **Cache semântico** (`lib/semantic_cache.rb`, `lib/cached_rag.rb`): reaproveita resposta de pergunta reformulada, com um cache por filtro de metadados.
> - **Model routing** (`lib/model_router.rb`): pergunta simples para o modelo barato, analítica para o forte. **A classe existe e é testada, mas não está no caminho da pergunta** — o `Api.llm_for` monta um modelo só. Ligá-la depende de resolver três acoplamentos com a observabilidade, e conferir se ficaram certos exige dois modelos reais respondendo — por isso anda junto com a [#26](https://github.com/Hirley/AIAD/issues/26).
>
> Fora da trilha, para tornar tudo isso utilizável: **API HTTP com controle de acesso** (chave por escopo, `lib/api/`) e **deploy em Docker** (API + Qdrant no compose), com o CI subindo a stack e testando o fluxo real.

## Fase 3: Agentes de IA & Fluxos Autônomos
**Foco:** Criação de sistemas que executam ações de forma autônoma.

- Arquiteturas de Agentes:
  - Padrões ReAct (Reasoning + Acting), Plan-and-Solve e uso de ferramentas (Tool Use / Function Calling).
- Orquestração de Frameworks:
  - Construção de grafos de estado e agentes multi-agente utilizando LangGraph ou CrewAI.
  - Persistência de estado de conversa e gerenciamento de memória em agentes.

> Issue: [#3](https://github.com/Hirley/AIAD/issues/3) — **concluída**
>
> Entregue via TDD/BDD, tudo testável sem chamada a modelo externo:
>
> - **ReAct (`lib/react_agent.rb`, `lib/react_parser.rb`):** laço pensamento → ação → observação, com teto de iterações, erro de ferramenta virando observação e o trajeto registrado para auditoria. O parser é separado do agente: ele corta a "Observação:" que o modelo escreve sozinho e dá precedência à ação quando o modelo responde junto com ela.
> - **Tool Use (`lib/tool.rb`, `lib/tool_registry.rb`, `lib/retrieval_tool.rb`):** ferramenta com descrição obrigatória (é o que o modelo lê para escolher) e validação estrita dos argumentos nos dois sentidos. No registro, ferramenta inexistente, argumento errado e falha interna viram texto de observação em vez de derrubar o laço.
> - **Plan-and-Solve (`lib/plan_and_solve_agent.rb`, `lib/plan_parser.rb`):** o plano inteiro antes da primeira ação, execução passo a passo alimentando o seguinte e síntese no fim. Teto de passos, plano ilegível caindo para um passo só (a própria pergunta) e passo que não concluiu chegando marcado à síntese, para o modelo dizer o que faltou em vez de preencher a lacuna.
> - **Grafo de estado (`lib/state_graph.rb`):** nós que devolvem só o que mudou (fundido no estado, nunca substituído), arestas fixas e condicionais, teto de passos para ciclo que não fecha e conferência de montagem antes da primeira execução — nó sem saída e grafo sem entrada falham na hora, não no dia em que o ramo torto for percorrido. É o que LangGraph faz em Python, no tamanho que este projeto precisa.
> - **Multi-agente (`lib/agent_crew.rb`, `lib/specialist_tool.rb`):** time montado sobre o grafo, com rotear → executar → revisar e a revisão podendo devolver o trabalho com o motivo. O ciclo é o que justifica o grafo: numa lista de passos, "refaça com o que o revisor apontou" não tem como ser expresso. Especialista é ferramenta, então catálogo, validação e conversão de falha em texto vêm prontos do `ToolRegistry`.
> - **Memória e persistência (`lib/conversation_memory.rb`, `lib/conversation_store.rb`, `lib/file_conversation_store.rb`, `lib/conversational_agent.rb`):** turnos por conversa, orçamento de tokens que derruba o mais antigo primeiro e nunca a última fala, e store injetável — em memória por padrão, em disco quando o histórico precisa sobreviver ao processo. Os dois stores passam pelo mesmo contrato de teste. O `ConversationalAgent` é decorador: ReAct, Plan-and-Solve e o time ganham memória sem saber que ela existe.

## Fase 4: Observabilidade de Aplicações e LLMs
**Foco:** Garantia de confiabilidade, rastreabilidade e métricas de infraestrutura.

- Observabilidade Específica para LLMs (Langsmith & Langfuse):
  - Tracing de chamadas de LLMs, agentes e cadeias de RAG.
  - Monitoramento de latência, custo por requisição e contagem de tokens por usuário/sessão.
  - Avaliação contínua (Evaluation) de qualidade das respostas (Hallucination, Relevancy).
- Observabilidade Geral de Sistemas (Ecossistema Grafana):
  - Prometheus + Grafana: métricas de infraestrutura da aplicação (CPU, memória, throughput).
  - Loki: agregação e análise centralizada de logs das aplicações.
  - Integração de métricas de LLM com dashboards executivos no Grafana.

> Issue: [#4](https://github.com/Hirley/AIAD/issues/4) — **concluída**
>
> Entregue via TDD/BDD, com a stack de observabilidade rodando em Docker e verificada de ponta a ponta no CI:
>
> - **Tracing, métricas por sessão e avaliação contínua** ([#8](https://github.com/Hirley/AIAD/pull/8)): spans aninhados com duração e uso (`lib/tracer.rb`), acumulado por sessão (`lib/session_metrics.rb`) e pontuação de toda resposta assim que ela sai (`lib/evaluated_rag.rb`, `lib/answer_evaluator.rb`). São três notas separadas porque as falhas são diferentes: sustentação baixa é o modelo inventando, relevância de contexto baixa é a recuperação trazendo lixo, relevância de resposta baixa é o modelo respondendo outra pergunta.
> - **`/metrics` e log estruturado** ([#9](https://github.com/Hirley/AIAD/pull/9)): registro de métricas sob mutex com rótulo declarado (`lib/metric_registry.rb`), exposição no formato do Prometheus (`lib/prometheus_exposition.rb`) e uma linha JSON por requisição com id correlacionável (`lib/api/request_logger.rb`). O `/metrics` exige o escopo `metrics`, separado de propósito: o Prometheus não precisa ler documento.
> - **Prometheus, Grafana e Loki** ([#11](https://github.com/Hirley/AIAD/pull/11)): stack atrás do profile `observabilidade`, com dois painéis provisionados **por arquivo** em `observability/grafana/dashboards/` — painel que só existe no banco do Grafana morre com o volume e ninguém revisa num pull request.
> - **Langfuse** ([#14](https://github.com/Hirley/AIAD/pull/14)): exportador em lote para o trace de LLM, ao lado do Prometheus e não no lugar dele — o Prometheus diz que o custo subiu ontem às 3h, o Langfuse diz por quê. Sem as duas chaves o exportador não é montado e a aplicação sobe igual. **Limite conhecido:** o formato do payload nunca foi verificado contra uma instância real.
> - **Juiz de sustentação por modelo** ([#32](https://github.com/Hirley/AIAD/pull/32)): a heurística léxica confunde paráfrase correta com alucinação — medido, 0,11 contra 0,17, faixas sobrepostas —, e o `lib/llm_judge.rb` é a saída. Fica **fora do padrão** por decisão explícita: ele chama o modelo uma vez por frase, não por resposta.
> - **Baldes por nota e o painel da distribuição** ([#34](https://github.com/Hirley/AIAD/pull/34)): uma lista de cortes para as três notas descrevia uma faixa que a aritmética não povoa — as notas são razões de inteiros pequenos, e cair entre 0,9 e 1,0 exige denominador maior que dez. Cada nota ganhou a sua, e entrou o painel que lê os baldes em vez da média, que é o que mostra a segunda corcova.
> - **Custo e tokens de verdade** ([#38](https://github.com/Hirley/AIAD/pull/38)): o preço nunca chegava ao exportador e o `usage` que o provedor devolve era descartado, então o painel de custo mostrava zero e os tokens eram estimativa. O preço vem do ambiente (sem tabela embutida, que envelheceria em silêncio) e o uso medido ganha do estimado, marcado com `measured` para dar para saber qual é qual.
>
> A regra que atravessa a fase: **"responde 200 mas está degradado" é o pior tipo de defeito**. Todo caminho de degradação silenciosa ganhou log estruturado e/ou métrica, e o `rescue` passou a ser do tamanho exato do que se sabe que pode falhar ([#30](https://github.com/Hirley/AIAD/pull/30)).

## Projeto Prático Integrador
Assistente Inteligente de Análise de Documentos, consolidando as quatro fases:

1. **ETL & Qdrant:** pipeline que ingere relatórios, gera embeddings e salva no Qdrant.
2. **RAG & Agente:** agente que consulta o Qdrant via RAG avançado e usa ferramentas externas para responder.
3. **Otimização:** cache semântico e compactação de histórico para economizar tokens.
4. **Observabilidade:** monitoramento do agente via Langfuse (prompts/respostas) e Grafana (saúde e métricas do servidor).

> Issue: [#5](https://github.com/Hirley/AIAD/issues/5) — **concluída**
>
> O assistente roda de ponta a ponta: `docker compose up` sobe API e Qdrant, o CI ingere documento, pergunta e confere a resposta contra o acervo real a cada PR. O que a consolidação exigiu, além de juntar as quatro fases:
>
> - **Agente ligado à API, com memória com teto** ([#12](https://github.com/Hirley/AIAD/pull/12), [#13](https://github.com/Hirley/AIAD/pull/13)): a rota `/agent` só existe quando há modelo de verdade — sem `ANTHROPIC_API_KEY` responde 503 dizendo o que configurar, em vez de montar um ReAct sobre um modelo extrativo que nunca escreveria "Pensamento / Ação". A memória tem teto de sessões porque sem ele uma sessão nova por pergunta enche o processo até ele morrer, semanas depois, sem nada apontando a causa.
> - **Piso de relevância** ([#15](https://github.com/Hirley/AIAD/pull/15), [#17](https://github.com/Hirley/AIAD/pull/17)): a API recusa a pergunta que o acervo não cobre em vez de citar o documento menos ruim com convicção. Nasce ligado: responder errado com confiança é pior do que recusar, e esse não é o padrão que se deixa para quem esquecer de configurar.
> - **Busca por radical** ([#16](https://github.com/Hirley/AIAD/pull/16)): o braço léxico passou a casar radical em vez de palavra inteira, então "férias" encontra "feriado" e plural deixa de ser outra palavra.
> - **Console web servido pela própria API** ([#18](https://github.com/Hirley/AIAD/pull/18), [#29](https://github.com/Hirley/AIAD/pull/29)): três operações — perguntar, buscar, ingerir — na mesma origem, sem CORS. A chave vive só numa variável do script, nunca em `sessionStorage`: o preço é redigitá-la a cada reload, e o que se compra é que um XSS não leva a credencial junto.
> - **Índice léxico reconstruído na partida** ([#20](https://github.com/Hirley/AIAD/pull/20), [#21](https://github.com/Hirley/AIAD/pull/21), [#30](https://github.com/Hirley/AIAD/pull/30)): o `Bm25Index` vive em memória, então todo restart apagava metade da busca híbrida — a API subia saudável, respondia 200 e buscava só pelo vetor. Agora o acervo é varrido antes de o Puma abrir a porta, com teto de trechos e de tempo, e a partida escreve no log **por que** o índice ficou parcial, quando ficou.
> - **Distribuível como gem** ([#33](https://github.com/Hirley/AIAD/pull/33)): publicada no GitHub Packages por tag. O pacote leva só nome e versão de propósito — as classes não têm namespace `Aiad::`, e embarcá-las poria `Tool`, `Tracer` e `Stemmer` no load path de quem instalasse.
> - **O fluxo de trabalho escrito** ([#31](https://github.com/Hirley/AIAD/pull/31)): as convenções do projeto — TDD/BDD, commit em ASCII, degradação nunca silenciosa — saíram do tácito para o [CLAUDE.md](CLAUDE.md).
