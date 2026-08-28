# language: pt
Funcionalidade: Agente ReAct com uso de ferramentas
  Como usuário do assistente de análise de documentos
  Eu quero um agente que decida sozinho quando consultar o acervo
  Para que ele responda com base no que consultou, e não no que imagina

  Contexto:
    Dado que o agente tem acesso aos documentos:
      | origem       | conteudo                                          |
      | politica.txt | A política de férias garante trinta dias por ano. |
      | servidor.txt | O servidor de produção reinicia toda madrugada.   |

  Cenário: O agente consulta o acervo antes de responder
    Dado que o modelo responderá, em sequência:
      """
      Pensamento: isso está na política de RH.
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      ---
      Pensamento: o trecho responde a pergunta.
      Resposta Final: São trinta dias por ano.
      """
    Quando eu peço ao agente "quantos dias de férias por ano?"
    Então a resposta do agente deve ser "São trinta dias por ano."
    E o agente deve ter usado a ferramenta "buscar_documentos"
    E a observação da ferramenta deve conter "trinta dias"
    E a observação da ferramenta deve citar a origem "politica.txt"

  Cenário: O agente responde direto quando não precisa de ferramenta
    Dado que o modelo responderá, em sequência:
      """
      Pensamento: é só um cumprimento.
      Resposta Final: Bom dia! Em que posso ajudar?
      """
    Quando eu peço ao agente "bom dia"
    Então a resposta do agente deve ser "Bom dia! Em que posso ajudar?"
    E o agente não deve ter usado nenhuma ferramenta

  # O vício mais comum do modelo é escrever a trajetória inteira sozinho,
  # inventando o resultado da ferramenta. Aqui ele tenta, e o agente ignora.
  Cenário: O agente ignora a observação que o modelo inventou
    Dado que o modelo responderá, em sequência:
      """
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      Observação: a política concede noventa dias.
      Resposta Final: São noventa dias.
      ---
      Resposta Final: São trinta dias por ano.
      """
    Quando eu peço ao agente "quantos dias de férias por ano?"
    Então o agente deve ter buscado exatamente "férias"
    E a observação da ferramenta deve conter "trinta dias"
    E a resposta do agente deve ser "São trinta dias por ano."

  Cenário: O agente se recupera de uma ferramenta que falhou
    Dado que a busca nos documentos está fora do ar
    E que o modelo responderá, em sequência:
      """
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      ---
      Pensamento: a busca falhou, preciso avisar.
      Resposta Final: Não consegui consultar os documentos agora.
      """
    Quando eu peço ao agente "quantos dias de férias por ano?"
    Então a observação da ferramenta deve conter "Erro"
    E a resposta do agente deve ser "Não consegui consultar os documentos agora."

  Cenário: O agente admite que não concluiu ao bater no limite de passos
    Dado que o agente pode dar no máximo 2 passos
    E que o modelo responderá, em sequência:
      """
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      ---
      Ação: buscar_documentos
      Entrada: {"termo": "descanso"}
      """
    Quando eu peço ao agente "quantos dias de férias por ano?"
    Então o agente deve informar que não concluiu
    E o agente deve ter feito 2 chamadas ao modelo
