# frozen_string_literal: true

# Juiz de sustentação por modelo de linguagem: pergunta ao modelo se uma
# afirmação se apoia num contexto, em vez de medir sobreposição de vocabulário.
# É o `judge:` que o cabeçalho do `AnswerEvaluator` já previa como saída para o
# limite medido lá — paráfrase correta e alucinação pura tiram a mesma nota
# léxica, porque nenhuma das duas reaproveita as palavras do trecho.
#
# Duas decisões definem o comportamento:
#
# - **`llm:` é qualquer coisa que responda a `complete(prompt)`**, a mesma
#   interface mínima que o `AnthropicLlm` já cumpre. Um double de teste e o
#   modelo de verdade passam pelo mesmo caminho, sem transporte HTTP novo
#   nenhum aqui.
# - **Sem `rescue`.** Erro do `llm` — rede, credencial, formato — propaga. Quem
#   já trata isso é o `EvaluatedRag#evaluate`, com `rescue StandardError; nil`
#   de propósito, pela mesma inversão "quem observa não derruba quem faz"
#   documentada no cabeçalho dele. Um segundo `rescue` aqui esconderia a mesma
#   coisa duas vezes.
#
# Não é o padrão do `AnswerEvaluator` — ver a decisão em `Api.answer_evaluator_for`
# — porque `@judge.call` é chamado uma vez por **frase** da resposta, não uma
# vez por resposta inteira: quatro frases são quatro chamadas de modelo.
class LlmJudge
  PROMPT = <<~PROMPT
    Contexto:
    %<context>s

    Afirmação:
    %<sentence>s

    A afirmação acima está sustentada pelo contexto? Considere sinônimo e
    paráfrase como sustentação válida; só responda "não" quando a afirmação
    contradiz o contexto ou afirma algo que ele não permite concluir.
    Responda só com "sim" ou "não".
  PROMPT

  def initialize(llm:)
    @llm = llm
  end

  def call(sentence, context)
    resposta = @llm.complete(format(PROMPT, sentence: sentence, context: context))

    supported?(resposta) ? 1.0 : 0.0
  end

  private

  def supported?(resposta)
    resposta.to_s.strip.downcase.start_with?('sim')
  end
end
