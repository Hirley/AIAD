# language: pt
Funcionalidade: RAG avançado e controle de custos
  Como responsável pelo assistente de análise de documentos
  Eu quero recuperação mais precisa e gasto de tokens sob controle
  Para que a resposta melhore sem que a conta cresça junto

  Contexto:
    Dado que o assistente avançado indexou os documentos:
      | origem        | autor | conteudo                                                              |
      | politica.txt  | rh    | A política de férias garante trinta dias por ano para cada funcionário |
      | servidor.txt  | infra | O servidor de produção reinicia toda madrugada por causa do backup     |

  Cenário: Re-ranking promove o trecho que responde a pergunta
    Dado que o re-ranking está ligado
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    Então a resposta deve vir de "politica.txt"

  Cenário: Parent Document Retriever devolve o documento inteiro
    Dado que a recuperação por documento pai está ligada
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    Então o contexto usado deve ser o documento inteiro de "politica.txt"

  Cenário: HyDE reescreve a pergunta antes de buscar
    Dado que o HyDE está ligado
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    Então o modelo deve ter sido consultado para gerar a hipótese
    E a resposta deve vir de "politica.txt"

  Cenário: Contagem de tokens é devolvida a cada resposta
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    Então a resposta deve informar os tokens gastos no prompt e na geração

  Cenário: Compressão encaixa o contexto no orçamento
    Dado que o orçamento de contexto é de 10 tokens
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    Então o contexto enviado deve caber em 10 tokens

  Cenário: Cache semântico evita a segunda chamada ao modelo
    Dado que o cache semântico está ligado
    Quando eu pergunto ao assistente "quantos dias de férias por ano"
    E eu pergunto ao assistente "quantos dias de férias temos por ano"
    Então a segunda resposta deve ter vindo do cache
    E o modelo deve ter sido chamado apenas 1 vez
    E a segunda resposta não deve ter gasto tokens

  Cenário: Pergunta simples vai para o modelo barato
    Dado que o roteamento de modelos está ligado
    Quando eu pergunto ao assistente "qual o horário"
    Então a pergunta deve ter sido atendida pelo modelo "barato"

  Cenário: Pergunta analítica vai para o modelo forte
    Dado que o roteamento de modelos está ligado
    Quando eu pergunto ao assistente "compare as políticas de férias e de backup"
    Então a pergunta deve ter sido atendida pelo modelo "forte"
