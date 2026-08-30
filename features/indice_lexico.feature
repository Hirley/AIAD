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

  # A varredura roda antes de o Puma abrir a porta. Sem teto, acervo grande
  # trocaria "sobe e busca pela metade" por "não sobe" — que é pior, porque
  # derruba readiness probe e põe o contêiner em loop de reinício.
  Cenário: Acervo maior que o teto sobe com o índice parcial, e diz que é parcial
    Dado que o acervo tem o documento "a.txt" com "férias de trinta dias"
    E que o acervo tem o documento "b.txt" com "reembolso de viagem"
    E que o acervo tem o documento "c.txt" com "trabalho remoto híbrido"
    Quando a API reinicia com teto de 2 trechos
    Então o índice léxico deve ter 2 trechos
    E o índice deve estar marcado como parcial

  # Métrica serve a quem está olhando um painel, e ninguém olha painel durante
  # um boot: quem sobe o contêiner e vê a API respondendo 200 lê log. E o par
  # de métricas diz que o índice ficou pela metade sem dizer **por quê** —
  # teto de trechos, teto de tempo e acervo inalcançável saem iguais lá.
  Cenário: A partida diz no log por que o índice ficou parcial
    Dado que o acervo tem o documento "a.txt" com "férias de trinta dias"
    E que o acervo tem o documento "b.txt" com "reembolso de viagem"
    E que o acervo tem o documento "c.txt" com "trabalho remoto híbrido"
    Quando a API reinicia com teto de 2 trechos
    Então o log da partida deve dar "max_documents" como motivo

  Cenário: Acervo vazio não impede a partida
    Quando a API reinicia com o mesmo acervo
    Então o índice léxico deve ter 0 trechos
    # Zero trecho de um acervo vazio é um índice completo: não falta nada. É o
    # que distingue "não há documento" de "não consegui ler o acervo".
    E o índice deve estar marcado como completo
    E o log da partida não deve dar motivo nenhum

  # A degradação continua existindo quando o Qdrant não responde; o que não
  # pode é ela derrubar o processo.
  Cenário: Qdrant fora do ar não impede a partida
    Dado que o acervo tem o documento "politica-ferias.txt" com "a política de férias garante trinta dias corridos"
    Quando a API reinicia com o Qdrant fora do ar
    Então o índice léxico deve ter 0 trechos
    E a partida não deve ter falhado
    # Zero e **parcial**, ao contrário do acervo vazio. É o par de métricas que
    # separa "não há documento" de "não consegui ler".
    E o índice deve estar marcado como parcial
    E o log da partida deve dar "unreachable" como motivo

  # O `rescue StandardError` que existia aqui engolia defeito de programação
  # junto com Qdrant fora do ar, e os dois saíam idênticos: zero trechos,
  # índice parcial. O disfarce durava semanas, porque a API responde 200 o
  # tempo todo e a busca fica com um braço só sem ninguém reparar.
  #
  # Agora o esperado degrada e o inesperado derruba a partida — a mesma escolha
  # que o console já faz quando a página não veio na imagem: falhar na
  # montagem, e não na primeira visita.
  Cenário: Defeito de programação na partida não se disfarça de acervo inalcançável
    Dado que o acervo tem o documento "politica-ferias.txt" com "a política de férias garante trinta dias corridos"
    Quando a API reinicia com um defeito no índice
    Então a partida deve ter falhado
    E o log da partida deve estar vazio
