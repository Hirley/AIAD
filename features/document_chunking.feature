# language: pt
Funcionalidade: Divisão de documentos em chunks
  Como usuário do assistente de análise de documentos
  Eu quero que o conteúdo ingerido seja dividido em pedaços menores
  Para que os embeddings sejam gerados com granularidade adequada para busca no Qdrant

  Cenário: Divisão de um texto maior que o tamanho do chunk
    Dado que eu tenho o conteúdo "abcdefghijklmn"
    Quando eu envio o documento para ingestão
    E eu divido o conteúdo em chunks de tamanho 10 com sobreposição de 2
    Então devo receber mais de um chunk
    E cada chunk deve ter no máximo 10 caracteres

  Cenário: Texto menor que o tamanho do chunk não é dividido
    Dado que eu tenho o conteúdo "curto"
    Quando eu envio o documento para ingestão
    E eu divido o conteúdo em chunks de tamanho 10 com sobreposição de 2
    Então devo receber exatamente 1 chunk
