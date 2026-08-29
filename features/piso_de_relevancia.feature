# language: pt
Funcionalidade: Piso de relevância nas respostas
  Como quem depende das respostas do assistente
  Eu quero que ele recuse o que o acervo não cobre
  Para não tomar decisão em cima de uma resposta confiante e errada

  # Sem Contexto de propósito: cada cenário monta a sua aplicação. Trocar de
  # aplicação no meio de um cenário não funciona — o Rack::Test memoiza a
  # sessão na primeira, e as requisições seguintes continuam indo para ela em
  # silêncio, o que faz um cenário testar o contrário do que diz testar.

  Cenário: Pergunta coberta pelo acervo continua sendo respondida
    Dado que a API com piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E a resposta da API deve citar a origem "politica-ferias.txt"

  # O defeito que motivou o piso: perguntado sobre assunto que não estava em
  # documento nenhum, o assistente respondia com a política de férias, citando
  # a origem, com toda a convicção de uma resposta certa.
  Cenário: Pergunta que nenhum documento cobre é recusada
    Dado que a API com piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "qual a política de plano de saúde odontológico" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E a resposta deve dizer que não encontrou

  # Recusar citando origem seria pior do que responder errado: daria ao "não
  # encontrei" a aparência de estar apoiado em documento.
  Cenário: A recusa não cita origem nenhuma
    Dado que a API com piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "quantos dias tenho de aviso prévio" com a chave "chave-leitura"
    Então a resposta não deve citar origem nenhuma

  Cenário: A recusa não gasta chamada ao modelo
    Dado que a API com piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "como funciona a participação nos lucros" com a chave "chave-leitura"
    Então a resposta não deve ter gasto token nenhum

  # O piso corta trecho a trecho: o que sobra é contexto menor e mais limpo,
  # não contexto nenhum.
  Cenário: O piso descarta só o que não pertence
    Dado que a API com piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta da API não deve citar a origem "politica-reembolso.txt"

  # A pergunta é escolhida a dedo: "dias" casa no braço léxico com a política
  # de férias, então há mesmo o que recusar. Uma pergunta que não recupera nada
  # não provaria nada — o caminho de "não recuperei" já existia antes do piso.
  Cenário: Sem piso configurado, o comportamento antigo continua disponível
    Dado que a API sem piso de relevância está no ar com as políticas ingeridas
    Quando eu pergunto "quantos dias tenho de aviso prévio" com a chave "chave-leitura"
    Então a resposta deve citar alguma origem
