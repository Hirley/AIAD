# language: pt
Funcionalidade: Cliente do Qdrant
  Como desenvolvedor do assistente de análise de documentos
  Eu quero um cliente que gerencie coleções e pontos no Qdrant
  Para que os chunks de documentos possam ser armazenados, buscados por similaridade e removidos

  Cenário: Criação de uma coleção e indexação de pontos
    Dado que o Qdrant está disponível
    Quando eu crio a coleção "documentos" com vetores de tamanho 3 e distância "Cosine"
    E eu indexo os pontos dos chunks "abc" e "def" na coleção "documentos"
    Então a coleção "documentos" deve ter sido criada com sucesso
    E 2 pontos devem ter sido enviados para a coleção "documentos"

  Cenário: Busca por similaridade retorna os pontos mais próximos
    Dado que o Qdrant está disponível
    E a coleção "documentos" possui pontos que respondem a uma busca com os resultados:
      | id | score |
      | 1  | 0.92  |
      | 2  | 0.81  |
    Quando eu busco na coleção "documentos" os 2 pontos mais próximos do vetor "0.1,0.2,0.3"
    Então devo receber 2 resultados da busca
    E o resultado mais relevante deve ser o ponto de id "1"

  Cenário: Busca por similaridade filtrando por metadado
    Dado que o Qdrant está disponível
    E a coleção "documentos" possui pontos que respondem a uma busca com os resultados:
      | id | score |
      | 3  | 0.88  |
    Quando eu busco na coleção "documentos" os 1 pontos mais próximos do vetor "0.1,0.2,0.3" com filtro "autor"="joao"
    Então devo receber 1 resultados da busca
    E a busca deve ter usado o filtro de metadado "autor" com valor "joao"

  Cenário: Consulta de existência e contagem de pontos da coleção
    Dado que o Qdrant está disponível
    E o Qdrant informa que a coleção "documentos" existe com 42 pontos
    Então a coleção "documentos" deve existir
    E a contagem de pontos da coleção "documentos" deve ser 42

  Cenário: Coleção criada com índice otimizado para busca vetorial
    Dado que o Qdrant está disponível
    Quando eu crio a coleção "documentos" com hnsw m=32 ef=200 e quantização "int8"
    Então a coleção "documentos" deve ter índice hnsw com m 32 e ef_construct 200
    E a coleção "documentos" deve usar quantização escalar "int8"

  Cenário: Ajuste da precisão da busca em tempo de consulta
    Dado que o Qdrant está disponível
    Quando eu busco na coleção "documentos" o vetor "0.1,0.2,0.3" com hnsw_ef 128
    Então a busca deve ter usado hnsw_ef 128

  Cenário: Ajuste do índice de uma coleção já existente
    Dado que o Qdrant está disponível
    Quando eu ajusto a coleção "documentos" para ef_construct 256
    Então o ajuste deve ter sido enviado como PATCH para a coleção "documentos"

  Cenário: Remoção de pontos e da coleção
    Dado que o Qdrant está disponível
    Quando eu crio a coleção "documentos" com vetores de tamanho 3 e distância "Cosine"
    E eu indexo os pontos dos chunks "abc" e "def" na coleção "documentos"
    E eu removo os pontos "1,2" da coleção "documentos"
    E eu removo a coleção "documentos"
    Então os pontos "1,2" devem ter sido removidos da coleção "documentos"
    E a coleção "documentos" deve ter sido removida
