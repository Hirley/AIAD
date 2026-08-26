# language: pt
Funcionalidade: Ingestão de documentos
  Como usuário do assistente de análise de documentos
  Eu quero enviar o conteúdo de um relatório
  Para que ele seja preparado para gerar embeddings e ser indexado no Qdrant

  Cenário: Ingestão de um documento válido
    Dado que eu tenho o conteúdo "  relatório trimestral de vendas  "
    Quando eu envio o documento para ingestão
    Então o conteúdo armazenado deve ser "relatório trimestral de vendas"

  Cenário: Rejeição de um documento vazio
    Dado que eu tenho o conteúdo "   "
    Quando eu envio o documento para ingestão
    Então devo receber um erro de conteúdo em branco
