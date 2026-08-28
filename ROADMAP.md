# Trilha de Aprendizagem — Engenharia de IA Aplicada (AIAD)

Trilha em quatro fases incrementais, do nível fundamental à produção e observabilidade avançada.
Acompanhamento das tarefas no board: https://github.com/users/Hirley/projects/4

## Setup do Projeto (TDD/BDD) — App base em Ruby
**Foco:** preparar o esqueleto do projeto seguindo TDD (unidade) e BDD (comportamento/aceitação), antes de incorporar o restante da trilha.

- **Setup:** rbenv/rvm (`.ruby-version`), Bundler (`Gemfile`), estrutura `app/`, `lib/`, `spec/`, `features/`.
- **TDD — RSpec:** ciclo Red → Green → Refactor. Unidades: `DocumentIngestor` (ingestão/normalização), `ContentCleaner` (limpeza por formato), `DocumentChunker` (chunking com overlap), `EmbeddingGenerator` (vetorização), `QdrantClient` (coleções, pontos e busca, com transporte injetável para testes sem servidor real) e `EtlPipeline` (orquestração).
- **BDD — Cucumber/Gherkin (pt):** cenários de aceitação em `features/document_ingestion.feature`, `features/document_chunking.feature`, `features/qdrant_client.feature` e `features/etl_pipeline.feature`, com os respectivos step definitions.
- **Qualidade/CI:** Rubocop (`.rubocop.yml`) e pipeline no GitHub Actions (`.github/workflows/ci.yml`) rodando `rubocop`, `rspec` e `cucumber` a cada push/PR.

> Issue: [#6](https://github.com/Hirley/AIAD/issues/6)

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
> - **Model routing** (`lib/model_router.rb`): pergunta simples para o modelo barato, analítica para o forte.
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

> Issue: [#4](https://github.com/Hirley/AIAD/issues/4)

## Projeto Prático Integrador
Assistente Inteligente de Análise de Documentos, consolidando as quatro fases:

1. **ETL & Qdrant:** pipeline que ingere relatórios, gera embeddings e salva no Qdrant.
2. **RAG & Agente:** agente que consulta o Qdrant via RAG avançado e usa ferramentas externas para responder.
3. **Otimização:** cache semântico e compactação de histórico para economizar tokens.
4. **Observabilidade:** monitoramento do agente via Langfuse (prompts/respostas) e Grafana (saúde e métricas do servidor).

> Issue: [#5](https://github.com/Hirley/AIAD/issues/5)
