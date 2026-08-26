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
