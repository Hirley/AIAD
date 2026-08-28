# language: pt
Funcionalidade: Time de agentes com roteamento e revisão
  Como usuário do assistente de análise de documentos
  Eu quero que a pergunta caia no especialista certo e passe por revisão
  Para que a resposta não dependa de um único agente acertar de primeira

  Contexto:
    Dado que o agente tem acesso aos documentos:
      | origem       | conteudo                                          |
      | politica.txt | A política de férias garante trinta dias por ano. |
      | servidor.txt | O servidor de produção reinicia toda madrugada.   |
    E que o time tem os especialistas:
      | nome  | descricao                              |
      | rh    | Sabe de férias, ponto e benefícios.    |
      | infra | Sabe de servidores, deploy e plantão.  |

  Cenário: A pergunta cai no especialista certo e a revisão aprova
    Dado que o roteador escolherá "infra"
    E que o especialista "infra" responderá, em sequência:
      """
      Ação: buscar_documentos
      Entrada: {"termo": "servidor reinicia"}
      ---
      Resposta Final: Reinicia toda madrugada.
      """
    E que a revisão dirá, em sequência:
      """
      APROVADO
      """
    Quando eu peço ao time "quando o servidor de produção reinicia?"
    Então o time deve ter acionado o especialista "infra"
    E a resposta do time deve ser "Reinicia toda madrugada."
    E a resposta do time deve estar aprovada
    E o caminho do time deve ser "rotear, executar, revisar"

  # Refazer sem saber o que estava errado é refazer igual.
  Cenário: A revisão devolve o trabalho com o motivo e o especialista refaz
    Dado que o roteador escolherá "rh"
    E que o especialista "rh" responderá, em sequência:
      """
      Resposta Final: Trinta dias.
      ---
      Resposta Final: Trinta dias corridos por ano, segundo politica.txt.
      """
    E que a revisão dirá, em sequência:
      """
      Faltou dizer se são corridos e de onde saiu a informação.
      ---
      APROVADO
      """
    Quando eu peço ao time "quantos dias de férias eu tenho?"
    Então o especialista "rh" deve ter recebido "Faltou dizer se são corridos"
    E a resposta do time deve ser "Trinta dias corridos por ano, segundo politica.txt."
    E o time deve ter feito 2 tentativas
    E o caminho do time deve ser "rotear, executar, revisar, executar, revisar"

  # Nome inventado não pode parar o time: alguém precisa atender.
  Cenário: O roteador escreve um nome que não existe
    Dado que o roteador escolherá "juridico"
    E que o especialista "rh" responderá, em sequência:
      """
      Resposta Final: Trinta dias por ano.
      """
    E que a revisão dirá, em sequência:
      """
      APROVADO
      """
    Quando eu peço ao time "quantos dias de férias eu tenho?"
    Então o time deve ter acionado o especialista "rh"
    E o time deve registrar que o roteamento falhou

  # Revisor exigente sem teto refaz para sempre, e cada volta é um agente inteiro.
  Cenário: O time entrega a resposta como está ao bater no teto de tentativas
    Dado que o time pode fazer no máximo 2 tentativas
    E que o roteador escolherá "rh"
    E que o especialista "rh" responderá, em sequência:
      """
      Resposta Final: Trinta dias.
      ---
      Resposta Final: Trinta dias, acho.
      """
    E que a revisão dirá, em sequência:
      """
      Ainda falta a fonte.
      ---
      Continua faltando a fonte.
      """
    Quando eu peço ao time "quantos dias de férias eu tenho?"
    Então a resposta do time não deve estar aprovada
    E o time deve ter feito 2 tentativas
