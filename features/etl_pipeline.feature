# language: pt
Funcionalidade: Pipeline de ETL de documentos
  Como desenvolvedor do assistente de análise de documentos
  Eu quero um pipeline que ingira, limpe, vetorize e indexe conteúdo não estruturado
  Para que documentos em texto, log ou PDF possam ser consultados por busca semântica

  Contexto:
    Dado que o pipeline de ETL está configurado

  Cenário: Ingestão de um documento em texto
    Quando eu ingiro o documento "politica.txt" no formato "texto" com o conteúdo:
      """
      A política de férias garante trinta dias por ano.
      """
    Então a coleção "documentos" deve ter sido criada com vetores de tamanho 32
    E 1 pontos devem ter sido indexados na coleção "documentos"
    E o ponto indexado deve ter origem "politica.txt" e formato "texto"

  Cenário: Ingestão de log descarta timestamp e nível
    Quando eu ingiro o documento "app.log" no formato "log" com o conteúdo:
      """
      2026-08-26T10:00:00Z ERROR Falha ao conectar no banco
      2026-08-26T10:00:01Z INFO  Conexão restabelecida
      """
    Então o texto indexado deve ser "Falha ao conectar no banco\nConexão restabelecida"

  Cenário: Ingestão de PDF remove marcador de página e junta palavras hifenizadas
    Quando eu ingiro o documento "contrato.pdf" no formato "pdf" com o conteúdo:
      """
      O docu-
      mento foi assinado.
      Página 1 de 3
      """
    Então o texto indexado deve ser "O documento foi assinado."

  Cenário: Reprocessar a mesma origem atualiza os pontos em vez de duplicar
    Quando eu ingiro o documento "politica.txt" no formato "texto" com o conteúdo:
      """
      A política de férias garante trinta dias por ano.
      """
    E eu reprocesso o documento "politica.txt" com o mesmo conteúdo
    Então os pontos indexados devem ter os mesmos ids do primeiro processamento

  Cenário: Busca semântica encontra o documento mais relevante
    Quando eu ingiro o documento "ferias.txt" no formato "texto" com o conteúdo:
      """
      A política de férias garante trinta dias por ano.
      """
    E eu ingiro o documento "servidor.txt" no formato "texto" com o conteúdo:
      """
      O servidor de produção reinicia toda madrugada.
      """
    E eu consulto "quantos dias de férias por ano" na coleção "documentos"
    Então o ponto mais similar deve ser o do documento "ferias.txt"
