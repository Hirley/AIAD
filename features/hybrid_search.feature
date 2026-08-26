# language: pt
Funcionalidade: Busca híbrida (vetorial + BM25)
  Como usuário do assistente de análise de documentos
  Eu quero que a recuperação combine similaridade semântica com correspondência léxica
  Para que termos exatos, como códigos de erro, não se percam na busca vetorial

  Contexto:
    Dado que o assistente indexou nos dois índices os documentos:
      | origem        | autor | conteudo                                          |
      | incidente.txt | infra | O erro ERR-4021 derruba o cluster de produção     |
      | manual.txt    | infra | Guia de operação do cluster e de boas práticas    |
      | politica.txt  | rh    | A política de férias garante trinta dias por ano  |

  Cenário: O que os dois braços concordam fica no topo
    Quando eu busco por "cluster de produção" com busca híbrida
    Então o resultado mais relevante deve ser de "incidente.txt"
    E o resultado mais relevante deve ter sido encontrado pelos dois braços

  # O embedder padrão é lexical por natureza (hashing de termos), então aqui os
  # dois braços concordariam sempre. O cenário declara a premissa com um dublê:
  # é o que acontece com embeddings reais, que capturam sentido e não o token
  # exato, e por isso perdem código de erro, sigla e número de contrato.
  Cenário: O braço léxico recupera o que a busca vetorial não trouxe
    Dado que o braço vetorial só encontra "manual.txt"
    Quando eu busco por "ERR-4021" com busca híbrida
    Então algum resultado deve ser de "incidente.txt"
    E o resultado de "incidente.txt" deve ter sido encontrado apenas pelo braço léxico

  Cenário: O filtro de metadados vale para os dois braços
    Quando eu busco por "cluster de produção" com busca híbrida filtrando pelo autor "rh"
    Então nenhum resultado deve ser de "incidente.txt"
    E nenhum resultado deve ser de "manual.txt"

  Cenário: A resposta do RAG usa a recuperação híbrida
    Quando eu pergunto ao RAG híbrido "o que derruba o cluster"
    Então a resposta do RAG deve citar a origem "incidente.txt"
