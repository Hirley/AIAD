# language: pt
Funcionalidade: API HTTP com controle de acesso
  Como responsável pelo assistente de análise de documentos
  Eu quero que a API exija chave e respeite escopos
  Para que só quem tem permissão consulte os documentos, e só quem tem permissão os ingira

  Contexto:
    Dado que a API está no ar com as chaves:
      | nome     | chave         | escopos    |
      | leitor   | chave-leitura | read       |
      | ingestor | chave-total   | read,write |

  Cenário: O health check é público
    Quando eu chamo "GET" em "/health" sem credencial
    Então a resposta deve ter status 200

  Cenário: Sem credencial não se consulta nada
    Quando eu chamo "POST" em "/search" sem credencial
    Então a resposta deve ter status 401
    E a resposta deve indicar o esquema "Bearer"

  Cenário: Chave inválida é recusada
    Quando eu chamo "POST" em "/search" com a chave "chave-inventada"
    Então a resposta deve ter status 401

  Cenário: Chave de leitura não pode ingerir documento
    Quando eu ingiro um documento com a chave "chave-leitura"
    Então a resposta deve ter status 403
    E a resposta deve dizer que falta o escopo "write"

  Cenário: Com a chave certa, ingestão e pergunta funcionam
    Quando eu ingiro um documento com a chave "chave-total"
    Então a resposta deve ter status 201
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E a resposta da API deve citar a origem "politica.txt"

  Cenário: A resposta da API não expõe o prompt enviado ao modelo
    Quando eu ingiro um documento com a chave "chave-total"
    E eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta não deve conter o campo "prompt"
