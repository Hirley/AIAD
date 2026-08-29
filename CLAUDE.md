# Fluxo de trabalho agêntico do AIAD

Este arquivo descreve **como trabalhar** neste repositório, não **o que ele faz** — isso está no
[README.md](README.md) e na [ROADMAP.md](ROADMAP.md). Ele existe porque o projeto já operava com estas
convenções de forma tácita, deduzíveis só lendo `git log` e os comentários no código; este arquivo as
torna explícitas para qualquer sessão de agente que entrar aqui, humana ou não.

## O ciclo, em ordem

1. **Planejar** antes de tocar em código, quando a mudança não for trivial.
2. **Vermelho** — escrever o cenário/teste que falha.
3. **Verde** — o mínimo de código para passá-lo.
4. **Lint** — RuboCop limpo antes de qualquer commit.
5. **Observar** — se o comportamento pode falhar em silêncio, ele precisa de log e/ou métrica.
6. **Commitar e documentar a verificação real** — não só "os testes passam".
7. **CI** — o que roda localmente é um subconjunto do que roda lá; nunca o contrário.

Cada etapa está detalhada abaixo.

## 1. Planejar

Para qualquer mudança que não seja um ajuste de uma linha, monte o plano antes de editar: qual arquivo
muda, qual decisão de projeto está em jogo, o que fica documentado como comentário e o que vira parágrafo
de commit. Este projeto tem histórico de **decisões erradas registradas e depois corrigidas** (ex.:
commit `7dbf09e`, sobre `preload_app!` e workers) — o plano é o lugar para pegar isso antes de escrever,
não depois.

Issues e o [board do projeto](https://github.com/users/Hirley/projects/4) (GitHub Projects V2, campos
Status/Priority/Size) são a fonte do que fazer a seguir. Uma issue bem escrita aqui já contém a decisão de
design tomada (ver #19, #22, #23 como exemplos de issue com investigação anexada) — leia a issue inteira,
incluindo a seção "Onde já está registrado", antes de propor outra coisa.

## 2–3. TDD/BDD — vermelho, depois verde

Duas suítes, duas granularidades, nenhuma substitui a outra:

- **RSpec** (`spec/`) — unidade. Um `_spec.rb` por classe em `lib/`. TDD: o exemplo que descreve o
  comportamento novo entra primeiro, vermelho, e só então o código.
- **Cucumber** (`features/`) — aceitação, em **Gherkin escrito em português** (`# language: pt`). BDD: o
  cenário descreve o efeito observável de fora — o que uma pessoa vendo a API de fora enxergaria — não a
  implementação. Os passos ficam em `features/step_definitions/*_steps.rb`; um passo nunca deve
  **reproduzir** a política que o código de produção já implementa (isso já aconteceu neste repo — ver o
  histórico de `indice_lexico_steps.rb`, onde um `rescue` largo copiado no step escondia regressão no
  código real). Se o comportamento existe numa classe, o step chama a classe.

Onde rodar (não há Ruby fora do container):

```bash
docker compose run --rm test                          # rspec (comando padrão da imagem)
docker compose run --rm test bundle exec cucumber
docker compose run --rm test bundle exec rubocop
docker compose run --rm test bash -lc "bundle exec rubocop && bundle exec rspec && bundle exec cucumber"
```

O código entra por bind mount e as gems ficam em volume (`test_bundle`) — editar e rodar de novo não
reconstrói a imagem. Só reconstrua depois de mexer no `Gemfile`:
`docker compose --profile test build test`.

## 4. Lint

`RuboCop` roda com `NewCops: enable` — cops novos entram ligados. Exceções em `.rubocop.yml` **sempre**
vêm com um comentário explicando o motivo específico (veja o arquivo: cada `Exclude` tem um parágrafo
acima). Uma exceção sem justificativa por escrito é a próxima pessoa reabrindo a mesma discussão.

## 5. Observar

Este projeto trata "responde 200 mas está degradado" como o pior tipo de defeito, porque já aconteceu
mais de uma vez (índice léxico apagado no restart, `rescue StandardError` disfarçando erro de programação
de Qdrant fora do ar). A regra prática:

- **Todo caminho de degradação silenciosa ganha uma linha de log estruturado (JSON, um objeto por linha,
  em `$stdout`) e/ou uma métrica Prometheus**, não só um dos dois quando o outro também se aplica. O
  padrão do log de boot está em `lib/api/lexical_index_warmup.rb`: `ts`, `level`, `event`, e os campos que
  importam para aquele evento.
- **`rescue` é do tamanho exato do que se sabe que pode falhar** — nunca `StandardError`/`Exception` largo
  para "por garantia". Erro inesperado deve derrubar a partida (mesmo precedente do `Api::Console`
  recusando montar sem a página do console), não virar métrica de "serviço externo fora do ar".
- Métrica nova sem uma verificação no CI que a exercite é a mesma lacuna que o commit `2f9af6b` corrigiu
  — toda métrica nova precisa de uma asserção equivalente em `.github/workflows/ci.yml`.

A stack de observabilidade completa (Prometheus, Loki via Promtail, Grafana com os dois dashboards em
`observability/grafana/dashboards/`, e Langfuse opcional para trace de LLM) sobe com
`docker compose --profile observabilidade up -d` e não é necessária para o dia a dia de código.

## 6. Git

- **Assunto e corpo do commit em ASCII, sem acento**, em português — convenção deste repositório desde o
  primeiro commit; `git log` é a referência viva do tom.
- Corpo do commit explica **por quê**, não o que o diff já mostra. Quando uma decisão anterior estava
  errada (não só incompleta), diga isso explicitamente, como o commit `7dbf09e` fez.
- Fecha com um parágrafo "Verificado..." descrevendo o que foi checado contra a stack real rodando (não
  "os testes passam" — isso o CI já garante) e a linha
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` (ou `Claude Sonnet 5` / `Claude 5`, conforme o
  modelo que fez o trabalho).
- **Issues e corpo de PR usam acentuação normal** — só o commit é ASCII. Não misture os dois registros.
  PR referencia a issue com "Fecha #N."
- Nunca `--amend` em commit já publicado, nunca `push --force` sem pedir, nunca `--no-verify`.
- Antes de qualquer comando que descarte trabalho não commitado (`checkout`/`restore`/`reset`/`clean`),
  `git status` primeiro.

## 7. Docker

- **Ruby só existe dentro do container.** Não há Ruby na máquina de desenvolvimento — todo `bundle exec`
  passa por `docker compose run --rm test ...`.
- `AIAD_API_KEYS` precisa estar exportado no shell antes de **qualquer** comando `docker compose`,
  inclusive `down`: o compose interpola o arquivo inteiro antes de filtrar por profile, e a variável tem
  `:?` no serviço `api`.
- Serviços atrás de profile (`test`, `observabilidade`) usam `:-` em vez de `:?` nas variáveis, pelo
  mesmo motivo ao contrário: um `:?` ali derrubaria `docker compose up` de quem nunca vai usar aquele
  profile.
- O `Dockerfile` é multi-estágio: `build` (compila gems nativas, não vai para a imagem final) → `test`
  (gems de dev, roda via bind mount) → `runtime` (sem compilador, sem gems de teste, usuário não-root,
  `HEALTHCHECK` batendo em `/health`). Mudança em `public/` (o console web) precisa do `COPY` no estágio
  `runtime` — esquecer isso derruba a partida porque `Api::Console` lê o arquivo no boot, não na primeira
  visita.

## 8. CI

`.github/workflows/ci.yml` tem dois jobs, e os dois devem passar localmente antes de abrir PR:

- **`test`** — RuboCop, RSpec, Cucumber, via `ruby/setup-ruby` (sem Docker). É o espelho direto do que
  `docker compose run --rm test bash -lc "..."` roda local.
- **`docker`** — sobe a stack real (`docker compose up --build --wait`) e faz verificação HTTP de ponta a
  ponta: health check sem credencial, console servido pela imagem, degradação do `/agent` sem
  `ANTHROPIC_API_KEY`, escopos de autorização nas duas direções, formato Prometheus das métricas, log em
  JSON, ingestão real contra Qdrant, **sobrevivência ao restart** (índice léxico completo, não só
  presente — a lição do commit `2f9af6b`) e resiliência a Langfuse inalcançável. Roda **sem** as
  variáveis do profile `observabilidade`, de propósito: garante que quem só quer a API não precisa
  configurar Grafana.

Ao adicionar uma rota, variável de ambiente ou métrica nova, pergunte: "isso precisa de uma asserção nova
no job `docker`?" — quase sempre a resposta é sim, porque é o único lugar que exercita o boot completo
contra serviços reais.

## Convenções de código

- Comentário explica **por que**, incluindo a alternativa rejeitada e o motivo — nunca o que o código já
  diz por si (nomes bons substituem isso). Os cabeçalhos de classe deste repo (`AnswerEvaluator`,
  `Api::Retrieval`, `RelevanceFloor`) são o padrão a seguir: decisões numeradas, cada uma com o porquê.
- Injeção de dependência por argumento nomeado é o padrão do projeto (ver seção "Injeção de dependência"
  do README) — um colaborador substituível em teste, não instanciado dentro da classe.
- `.rubocop.yml` documenta toda exceção; siga o mesmo padrão ao adicionar uma nova.
