# language: pt
Funcionalidade: Agente Plan-and-Solve
  Como usuário do assistente de análise de documentos
  Eu quero um agente que monte o plano antes de começar a agir
  Para que perguntas com mais de uma apuração não sejam respondidas pela metade

  Contexto:
    Dado que o agente tem acesso aos documentos:
      | origem       | conteudo                                          |
      | politica.txt | A política de férias garante trinta dias por ano. |
      | servidor.txt | O servidor de produção reinicia toda madrugada.   |

  Cenário: O agente divide a pergunta em passos e apura cada um
    Dado que o planejador responderá:
      """
      1. Descobrir quantos dias de férias a política concede.
      2. Descobrir quando o servidor de produção reinicia.
      """
    E que a síntese do planejador será "São trinta dias de férias, e o servidor reinicia toda madrugada."
    E que o executor responderá, em sequência:
      """
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      ---
      Resposta Final: trinta dias por ano.
      ---
      Ação: buscar_documentos
      Entrada: {"termo": "servidor reinicia"}
      ---
      Resposta Final: toda madrugada.
      """
    Quando eu peço ao agente planejador "quantos dias de férias eu tenho e quando o servidor reinicia?"
    Então o plano deve ter 2 passos
    E o agente deve ter consultado os documentos 2 vezes
    E a resposta do agente deve ser "São trinta dias de férias, e o servidor reinicia toda madrugada."

  # Sem isso, o segundo passo recomeçaria do zero e o plano deixaria de ser plano.
  Cenário: Cada passo recebe o que os anteriores já apuraram
    Dado que o planejador responderá:
      """
      1. Descobrir quantos dias de férias a política concede.
      2. Converter esse número em semanas.
      """
    E que a síntese do planejador será "São trinta dias, cerca de quatro semanas."
    E que o executor responderá, em sequência:
      """
      Resposta Final: trinta dias por ano.
      ---
      Resposta Final: cerca de quatro semanas.
      """
    Quando eu peço ao agente planejador "quantas semanas de férias eu tenho?"
    Então a tarefa do passo 2 deve conter "trinta dias por ano."
    E a tarefa do passo 1 não deve conter "trinta dias por ano."

  # Prosa não é plano, mas também não é motivo para desistir da pergunta.
  Cenário: O agente resolve num passo só quando o planejador não escreve uma lista
    Dado que o planejador responderá:
      """
      Acho que basta olhar a política de RH e ver o número.
      """
    E que a síntese do planejador será "São trinta dias."
    E que o executor responderá, em sequência:
      """
      Resposta Final: trinta dias por ano.
      """
    Quando eu peço ao agente planejador "quantos dias de férias por ano?"
    Então o plano deve ter 1 passos
    E o plano deve ser a própria pergunta

  Cenário: O agente avisa quando um passo não concluiu, em vez de completar a lacuna
    Dado que cada passo pode dar no máximo 1 chamada ao modelo
    E que o planejador responderá:
      """
      1. Descobrir quantos dias de férias a política concede.
      2. Descobrir o orçamento do trimestre.
      """
    E que a síntese do planejador será "São trinta dias; não achei o orçamento do trimestre."
    E que o executor responderá, em sequência:
      """
      Resposta Final: trinta dias por ano.
      ---
      Ação: buscar_documentos
      Entrada: {"termo": "orçamento"}
      """
    Quando eu peço ao agente planejador "quantos dias de férias e qual o orçamento do trimestre?"
    Então o agente deve informar que um passo não concluiu
    E o modelo deve ter visto que um passo não concluiu antes de responder

  # Cada passo é uma execução inteira, com as chamadas de modelo dela.
  Cenário: O plano é cortado no limite de passos
    Dado que o agente pode seguir no máximo 2 passos
    E que o planejador responderá:
      """
      1. Um
      2. Dois
      3. Três
      4. Quatro
      """
    E que a síntese do planejador será "pronto."
    E que o executor responderá, em sequência:
      """
      Resposta Final: um
      ---
      Resposta Final: dois
      """
    Quando eu peço ao agente planejador "uma pergunta grande demais"
    Então o plano deve ter 2 passos
