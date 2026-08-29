# language: pt
Funcionalidade: Rota do agente na API
  Como responsável pelo assistente de análise de documentos
  Eu quero uma rota em que o agente decide sozinho o que buscar
  Para que perguntas que exigem mais de uma consulta sejam respondidas sem eu encadear chamadas

  Contexto:
    Dado que a API do agente está no ar com as chaves:
      | nome   | chave         | escopos |
      | leitor | chave-leitura | read    |
    E o acervo tem o documento "politica.txt" com "A política de férias garante trinta dias por ano."

  Cenário: O agente busca no acervo antes de responder
    Dado que o modelo vai responder:
      """
      Pensamento: preciso consultar a política.
      Ação: buscar_documentos
      Entrada: {"termo": "férias"}
      ---
      Pensamento: o trecho responde a pergunta.
      Resposta Final: Trinta dias por ano.
      """
    Quando eu pergunto ao agente "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E a resposta da API do agente deve ser "Trinta dias por ano."
    E a resposta do agente deve dizer que usou a ferramenta "buscar_documentos"
    E a resposta do agente deve dizer que concluiu

  # As observações são trechos de documento que o cliente não pediu — mesmo
  # motivo pelo qual o /ask não devolve o prompt.
  Cenário: O trajeto do agente não volta para o cliente
    Dado que o modelo vai responder:
      """
      Pensamento: já sei.
      Resposta Final: Trinta dias por ano.
      """
    Quando eu pergunto ao agente "quantos dias de férias" com a chave "chave-leitura"
    Então a resposta do agente não deve trazer o trajeto

  Cenário: A sessão volta na resposta, para a próxima pergunta continuar
    Dado que o modelo vai responder:
      """
      Pensamento: já sei.
      Resposta Final: Trinta dias por ano.
      """
    Quando eu pergunto ao agente "quantos dias de férias" com a chave "chave-leitura"
    Então a resposta do agente deve trazer uma sessão

  Cenário: A sessão informada é a que o agente usa
    Dado que o modelo vai responder:
      """
      Pensamento: já sei.
      Resposta Final: Trinta dias por ano.
      """
    Quando eu pergunto ao agente "e quantos períodos?" na sessão "conversa-1" com a chave "chave-leitura"
    Então a resposta do agente deve trazer a sessão "conversa-1"

  # A segunda pergunta chega ao modelo com a primeira junto: é isso que
  # permite perguntar "e quantos períodos?" sem repetir o assunto.
  Cenário: A segunda pergunta da sessão leva o histórico
    Dado que o modelo vai responder:
      """
      Pensamento: já sei.
      Resposta Final: Trinta dias por ano.
      ---
      Pensamento: já sei.
      Resposta Final: Até três períodos.
      """
    Quando eu pergunto ao agente "quantos dias de férias" na sessão "conversa-1" com a chave "chave-leitura"
    E eu pergunto ao agente "e quantos períodos?" na sessão "conversa-1" com a chave "chave-leitura"
    Então o modelo deve ter recebido a pergunta anterior junto

  Cenário: Sem credencial não se usa o agente
    Quando eu chamo "POST" em "/agent" sem credencial
    Então a resposta deve ter status 401

  # Falhar imediato dizendo o que configurar é melhor que dar seis voltas no
  # laço para devolver "não cheguei a uma conclusão".
  Cenário: Sem modelo configurado, a rota diz o que falta
    Dado que a API do agente está no ar sem modelo configurado
    Quando eu pergunto ao agente "quantos dias de férias" com a chave "chave-leitura"
    Então a resposta deve ter status 503
    E a resposta do agente deve dizer o que configurar
