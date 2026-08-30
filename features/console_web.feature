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

  # Aqui esteve um cenário que conferia que o corpo servido não continha as
  # chaves configuradas. Nada no caminho do código poderia pô-las ali: ele só
  # falharia se alguém as escrevesse na página de propósito. Tinha a aparência
  # de uma garantia de segurança sem ser uma.
  #
  # A propriedade que interessa é a de baixo, e ela é sobre o que a página faz
  # com a chave que **recebe**: não deixar cópia onde outro script desta origem
  # alcance — a mesma origem que serve o conteúdo dos documentos ingeridos.
  # Sem navegador, o que a suíte alcança é afirmar isso sobre o artefato
  # servido: nenhuma chamada a armazenamento do navegador sai daqui. É menos
  # que medir o disco depois de usar, e é o que dá para cobrar a cada push.
  Cenário: A página não tem onde guardar a chave fora da memória
    Quando eu chamo "GET" em "/" sem credencial
    Então a página servida não deve usar armazenamento do navegador

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
