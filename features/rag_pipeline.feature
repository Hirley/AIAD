# language: pt
Funcionalidade: Perguntas e respostas com RAG
  Como usuário do assistente de análise de documentos
  Eu quero perguntar em linguagem natural sobre os documentos indexados
  Para que a resposta venha ancorada nos trechos recuperados e com as origens citadas

  Contexto:
    Dado que o assistente indexou os documentos:
      | origem       | autor | conteudo                                          |
      | politica.txt | rh    | A política de férias garante trinta dias por ano. |
      | servidor.txt | infra | O servidor de produção reinicia toda madrugada.   |

  Cenário: A resposta é ancorada no documento mais relevante
    Quando eu pergunto "quantos dias de férias por ano"
    Então o contexto enviado ao modelo deve conter o trecho de "politica.txt"
    E a resposta deve citar a origem "politica.txt"
    E o prompt deve instruir o modelo a responder apenas com o contexto

  Cenário: O contexto pode ser restrito por metadado
    Quando eu pergunto "quando o sistema reinicia" filtrando pelo autor "infra"
    Então a resposta deve citar a origem "servidor.txt"
    E a resposta não deve citar a origem "politica.txt"

  Cenário: Pergunta sem contexto não gasta tokens
    Quando eu pergunto "qual o faturamento do trimestre" filtrando pelo autor "juridico"
    Então o modelo não deve ter sido chamado
    E a resposta deve informar que a informação não foi encontrada
