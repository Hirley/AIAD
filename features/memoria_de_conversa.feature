# language: pt
Funcionalidade: Memória de conversa do agente
  Como usuário do assistente de análise de documentos
  Eu quero que o agente lembre do que já foi dito na conversa
  Para que eu possa perguntar "e em semanas?" sem repetir a pergunta inteira

  Contexto:
    Dado que o agente tem acesso aos documentos:
      | origem       | conteudo                                          |
      | politica.txt | A política de férias garante trinta dias por ano. |

  # É todo o ponto da memória: "e em semanas?" não quer dizer nada sozinha.
  Cenário: A segunda pergunta enxerga o que já foi respondido
    Dado que o modelo responderá, em sequência:
      """
      Resposta Final: São trinta dias por ano.
      ---
      Resposta Final: Cerca de quatro semanas.
      """
    Quando eu pergunto na conversa "sessao-1" "quantos dias de férias eu tenho?"
    E eu pergunto na conversa "sessao-1" "e em semanas?"
    Então o agente deve ter visto "São trinta dias por ano." na última pergunta
    E a resposta da conversa deve ser "Cerca de quatro semanas."

  Cenário: A primeira pergunta não anuncia um histórico que não existe
    Dado que o modelo responderá, em sequência:
      """
      Resposta Final: São trinta dias por ano.
      """
    Quando eu pergunto na conversa "sessao-1" "quantos dias de férias eu tenho?"
    Então o agente não deve ter visto nenhum histórico na última pergunta

  Cenário: Conversas diferentes não se misturam
    Dado que o modelo responderá, em sequência:
      """
      Resposta Final: São trinta dias por ano.
      ---
      Resposta Final: Bom dia!
      """
    Quando eu pergunto na conversa "sessao-1" "quantos dias de férias eu tenho?"
    E eu pergunto na conversa "sessao-2" "bom dia"
    Então o agente não deve ter visto nenhum histórico na última pergunta
    E a conversa "sessao-2" deve ter 2 turnos guardados

  # O motivo de o store ser injetável: o histórico não pode morrer com o processo.
  Cenário: A conversa sobrevive ao assistente ser reiniciado
    Dado que a conversa é guardada em disco
    E que o modelo responderá, em sequência:
      """
      Resposta Final: São trinta dias por ano.
      ---
      Resposta Final: Cerca de quatro semanas.
      """
    Quando eu pergunto na conversa "sessao-1" "quantos dias de férias eu tenho?"
    E o assistente é reiniciado do zero
    E eu pergunto na conversa "sessao-1" "e em semanas?"
    Então o agente deve ter visto "São trinta dias por ano." na última pergunta

  # Conversa cresce sem parar e o histórico inteiro é pago em toda chamada.
  Cenário: O histórico é cortado no orçamento, mantendo o mais recente
    Dado que o histórico cabe em 6 tokens
    E que o modelo responderá, em sequência:
      """
      Resposta Final: São trinta dias por ano, segundo a política vigente.
      ---
      Resposta Final: Cerca de quatro semanas.
      ---
      Resposta Final: Vinte e um dias úteis.
      """
    Quando eu pergunto na conversa "sessao-1" "quantos dias de férias eu tenho?"
    E eu pergunto na conversa "sessao-1" "e em semanas?"
    E eu pergunto na conversa "sessao-1" "e em dias úteis?"
    Então o agente deve ter visto "Cerca de quatro semanas." na última pergunta
    E o agente não deve ter visto "segundo a política vigente" na última pergunta
    E a conversa "sessao-1" deve ter 6 turnos guardados
