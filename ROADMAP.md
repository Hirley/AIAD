# Trilha de Aprendizagem — Engenharia de IA Aplicada (AIAD)

Trilha em quatro fases incrementais, do nível fundamental à produção e observabilidade avançada.
Acompanhamento das tarefas no board: https://github.com/users/Hirley/projects/4

## Setup do Projeto (TDD/BDD) — App base em Ruby
**Foco:** preparar o esqueleto do projeto seguindo TDD (unidade) e BDD (comportamento/aceitação), antes de incorporar o restante da trilha.

- **Setup:** rbenv/rvm (`.ruby-version`), Bundler (`Gemfile`), estrutura `app/`, `lib/`, `spec/`, `features/`.
- **TDD — RSpec:** ciclo Red → Green → Refactor. Unidades: `DocumentIngestor` (ingestão/normalização), `DocumentChunker` (chunking com overlap) e `QdrantClient` (criação de coleções e indexação de pontos, com transporte injetável para testes sem servidor real).
- **BDD — Cucumber/Gherkin (pt):** cenários de aceitação em `features/document_ingestion.feature`, `features/document_chunking.feature` e `features/qdrant_client.feature`, com os respectivos step definitions.
- **Qualidade/CI:** Rubocop (`.rubocop.yml`) e pipeline no GitHub Actions (`.github/workflows/ci.yml`) rodando `rubocop`, `rspec` e `cucumber` a cada push/PR.

> Issue: [#6](https://github.com/Hirley/AIAD/issues/6)

## Fase 1: Fundamentos de Engenharia de Dados & Bancos Vetoriais
**Foco:** Construção e preparação do pipeline de entrada (ETL) e armazenamento para IA.

- Pipelines de ETL: processamento, limpeza e estruturação de dados não estruturados (PDFs, textos, logs).
- Bancos Vetoriais (Qdrant):
  - Conceitos de embeddings (vetorização de texto).
  - Indexação, distância vetorial (Cosine, Euclidean, Dot Product) e filtros de metadados.
  - Operações de CRUD de coleções e otimização de busca vetorial no Qdrant.

> Issue: [#1](https://github.com/Hirley/AIAD/issues/1)
>
> Progresso: `QdrantClient` (`lib/qdrant_client.rb`) implementado via TDD/BDD — cria coleções (`create_collection`) e indexa pontos (`upsert_points`) sobre um transporte injetável, testado sem depender de um servidor Qdrant real.

## Fase 2: Arquiteturas de RAG & Otimização de Tokens
**Foco:** Recuperação contextual eficiente e redução de custos.

- Retrieval-Augmented Generation (RAG):
  - RAG Básico (Chunking, Retrieval, Generation).
  - RAG Avançado: Hybrid Search (Busca Vetorial + BM25), Re-ranking, Parent Document Retriever e HyDE.
- Otimização de Custos e Performance:
  - Gestão e contagem de tokens em tempo real.
  - Técnicas de Prompt Compression e uso de Caching (ex: Semantic Cache).
  - Seleção dinâmica de modelos (Model Routing) com base em complexidade.

> Issue: [#2](https://github.com/Hirley/AIAD/issues/2)

## Fase 3: Agentes de IA & Fluxos Autônomos
**Foco:** Criação de sistemas que executam ações de forma autônoma.

- Arquiteturas de Agentes:
  - Padrões ReAct (Reasoning + Acting), Plan-and-Solve e uso de ferramentas (Tool Use / Function Calling).
- Orquestração de Frameworks:
  - Construção de grafos de estado e agentes multi-agente utilizando LangGraph ou CrewAI.
  - Persistência de estado de conversa e gerenciamento de memória em agentes.

> Issue: [#3](https://github.com/Hirley/AIAD/issues/3)

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
