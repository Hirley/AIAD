# frozen_string_literal: true

# Modelo de resposta extrativa: devolve, sem reescrever, o trecho mais relevante
# do contexto montado pelo PromptBuilder.
#
# Existe para que a API funcione de ponta a ponta sem nenhuma credencial de
# provedor de LLM — é um substituto honesto, não um gerador: ele nunca inventa
# conteúdo, só recorta. Para respostas geradas de verdade, injete um modelo real
# no RagPipeline; a interface é a mesma (`complete(prompt)`).
class ExtractiveLlm
  NO_ANSWER = 'Não encontrei essa informação nos documentos indexados.'
  FIRST_PASSAGE = /^\[1\]\s+\(origem:[^)]*\)\n(.+?)(?:\n\s*\n|\z)/m

  def complete(prompt)
    match = FIRST_PASSAGE.match(prompt.to_s)
    return NO_ANSWER if match.nil?

    "#{match[1].strip} [1]"
  end
end
