# language: pt
Funcionalidade: Cliente do Qdrant
  Como desenvolvedor do assistente de análise de documentos
  Eu quero um cliente que crie coleções e indexe pontos no Qdrant
  Para que os chunks de documentos possam ser armazenados e buscados por similaridade

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
