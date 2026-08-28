# language: pt
Funcionalidade: Métricas e log estruturado
  Como responsável pela operação do assistente
  Eu quero métricas no formato do Prometheus e uma linha de log por requisição
  Para que dê para ver o que o serviço está fazendo sem precisar ler o código

  Contexto:
    Dado que a API observada está no ar com as chaves:
      | nome       | chave          | escopos |
      | leitor     | chave-leitura  | read    |
      | prometheus | chave-metricas | metrics |

  Cenário: O Prometheus raspa as métricas com a chave certa
    Quando eu chamo "GET" em "/metrics" com a chave "chave-metricas"
    Então a resposta deve ter status 200
    E a resposta deve conter a métrica "aiad_process_cpu_seconds_total"

  Cenário: Sem credencial não se raspa métrica
    Quando eu chamo "GET" em "/metrics" sem credencial
    Então a resposta deve ter status 401

  Cenário: Quem lê documentos não vê a operação por dentro
    Quando eu chamo "GET" em "/metrics" com a chave "chave-leitura"
    Então a resposta deve ter status 403
    E a resposta deve dizer que falta o escopo "metrics"

  Cenário: A requisição atendida aparece na contagem
    Quando eu chamo "GET" em "/health" sem credencial
    E eu chamo "GET" em "/metrics" com a chave "chave-metricas"
    Então a resposta deve conter a métrica "aiad_http_requests_total"
    E a resposta deve contar 1 requisição em "/health" com status "200"

  # Um pico de 401 é chave rotacionada sem avisar ou alguém adivinhando
  # credencial: precisa aparecer no gráfico.
  Cenário: A requisição recusada também é contada
    Quando eu chamo "GET" em "/metrics" sem credencial
    E eu chamo "GET" em "/metrics" com a chave "chave-metricas"
    Então a resposta deve contar 1 requisição em "/metrics" com status "401"

  # Cardinalidade de rótulo é a forma mais comum de derrubar um Prometheus, e
  # vem de fora.
  Cenário: Caminho inventado não vira uma série temporal nova
    Quando eu chamo "GET" em "/caminho-de-um-varredor" sem credencial
    E eu chamo "GET" em "/metrics" com a chave "chave-metricas"
    Então a resposta deve conter a métrica "route=\"outra\""
    E a resposta não deve citar "caminho-de-um-varredor"

  Cenário: Cada requisição rende uma linha de log em JSON
    Quando eu chamo "GET" em "/health" sem credencial
    Então o log deve ter 1 linha em JSON
    E a linha de log deve registrar a rota "/health" com status 200

  Cenário: O log não guarda o corpo nem a credencial
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então o log não deve conter "quantos dias de férias por ano"
    E o log não deve conter "chave-leitura"

  Cenário: A resposta traz o id da requisição, para achar a linha de log depois
    Quando eu chamo "GET" em "/health" sem credencial
    Então a resposta deve trazer um id de requisição
