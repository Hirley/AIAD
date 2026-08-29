# language: pt
Funcionalidade: O índice léxico se reconstrói do acervo
  Como responsável pelo assistente
  Eu quero que o braço BM25 volte sozinho depois de um restart
  Para que a busca não degrade em silêncio para só o vetorial

  # O defeito que motivou tudo: o índice vive em memória, então reiniciar a API
  # apagava metade da busca híbrida. A API subia saudável, respondia 200, e
  # passava a buscar só pelo vetor — sem sinal nenhum de que tinha piorado.
  Cenário: Depois de reiniciar, o trecho continua achável pelo braço léxico
    Dado que o acervo tem o documento "politica-ferias.txt" com "a política de férias garante trinta dias corridos"
    E que a busca léxica encontra "férias"
    Quando a API reinicia com o mesmo acervo
    Então a busca léxica ainda deve encontrar "férias"

  Cenário: O índice reconstruído sabe de quantos trechos é feito
    Dado que o acervo tem o documento "politica-ferias.txt" com "a política de férias garante trinta dias corridos"
    E que o acervo tem o documento "politica-reembolso.txt" com "o reembolso de viagem cobre hospedagem"
    Quando a API reinicia com o mesmo acervo
    Então o índice léxico deve ter 2 trechos

  Cenário: Acervo vazio não impede a partida
    Quando a API reinicia com o mesmo acervo
    Então o índice léxico deve ter 0 trechos

  # A degradação continua existindo quando o Qdrant não responde; o que não
  # pode é ela derrubar o processo.
  Cenário: Qdrant fora do ar não impede a partida
    Dado que o acervo tem o documento "politica-ferias.txt" com "a política de férias garante trinta dias corridos"
    Quando a API reinicia com o Qdrant fora do ar
    Então o índice léxico deve ter 0 trechos
    E a partida não deve ter falhado
