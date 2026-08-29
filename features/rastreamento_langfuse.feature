# language: pt
Funcionalidade: Rastreamento das perguntas no Langfuse
  Como responsável pela qualidade das respostas do assistente
  Eu quero cada pergunta rastreada com prompt, resposta e tokens
  Para que dê para investigar uma resposta ruim olhando o que o modelo recebeu

  Contexto:
    Dado que a API rastreada está no ar com o Langfuse configurado
    E que um documento já foi ingerido

  Cenário: A pergunta respondida vira um trace
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então o Langfuse deve ter recebido 1 trace
    E o trace deve registrar a pergunta "quantos dias de férias por ano"
    E o trace deve registrar a resposta que a API devolveu

  # É a diferença entre "o custo subiu" e "o custo subiu por causa deste
  # prompt": o span da geração é o que carrega os tokens.
  Cenário: A chamada ao modelo aparece como geração, com os tokens
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então o Langfuse deve ter recebido 1 geração
    E a geração deve declarar os tokens gastos

  Cenário: Os passos internos aparecem aninhados sob o trace
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então o Langfuse deve ter recebido a observação "rag.retrieve"
    E toda observação deve apontar para o trace

  # A inversão que vale para qualquer observador: ninguém aceita cair porque
  # quem estava olhando caiu.
  Cenário: Langfuse fora do ar não derruba a resposta
    Dado que o Langfuse está fora do ar
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200

  # Se a queda do Langfuse levasse junto a métrica, um serviço fora do ar
  # apagaria justamente o número que se usa para perceber isso.
  Cenário: Langfuse fora do ar não leva junto a métrica do Prometheus
    Dado que o Langfuse está fora do ar
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então o Prometheus deve ter contado a chamada ao modelo

  Cenário: Sem chave configurada, nada é mandado e a API responde igual
    Dado que a API rastreada está no ar sem o Langfuse configurado
    E que um documento já foi ingerido
    Quando eu pergunto "quantos dias de férias por ano" com a chave "chave-leitura"
    Então a resposta deve ter status 200
    E o Langfuse não deve ter recebido nada
