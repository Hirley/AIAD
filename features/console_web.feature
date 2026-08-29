# language: pt
Funcionalidade: Console web servido pela própria API
  Como quem opera o assistente
  Eu quero uma página para ingerir, buscar e perguntar sem linha de comando
  Para que dá para usar o acervo sem montar requisição na mão

  Contexto:
    Dado que o console está no ar com as chaves:
      | nome     | chave         | escopos    |
      | leitor   | chave-leitura | read       |
      | ingestor | chave-total   | read,write |

  Cenário: A página abre sem credencial, porque é ela que pede a credencial
    Quando eu chamo "GET" em "/" sem credencial
    Então a resposta deve ter status 200
    E a página servida deve ser HTML

  # O que separa "página que pede a chave" de "página que vaza a chave".
  Cenário: A página não carrega nenhuma das chaves configuradas
    Quando eu chamo "GET" em "/" sem credencial
    Então a página servida não deve conter a chave "chave-total"
    E a página servida não deve conter a chave "chave-leitura"

  Cenário: A página pede a chave a quem abriu
    Quando eu chamo "GET" em "/" sem credencial
    Então a página servida deve ter um campo de senha para a chave

  # O console é middleware: se ele engolir requisição que não é dele, a API
  # inteira para de existir por trás de uma página.
  Cenário: O console não afrouxa o controle de acesso das outras rotas
    Quando eu chamo "POST" em "/search" sem credencial
    Então a resposta deve ter status 401

  Cenário: Só o GET da raiz é a página
    Quando eu chamo "POST" em "/" sem credencial
    Então a resposta deve ter status 401

  Cenário: Com o console na pilha, ingerir e perguntar continuam funcionando
    Quando eu ingiro um documento com a chave "chave-total"
    Então a resposta deve ter status 201
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E a resposta da API deve citar a origem "politica.txt"
