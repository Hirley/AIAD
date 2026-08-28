# frozen_string_literal: true

module Api
  # Tipo de conteúdo das respostas JSON da API.
  #
  # O `charset=utf-8` é explícito de propósito. Pela RFC 8259 todo JSON é UTF-8
  # e o parâmetro é redundante — mas cliente que não sabe disso assume
  # ISO-8859-1 e transforma "Não encontrei" em "NÃ£o encontrei". O
  # `Invoke-RestMethod` do Windows PowerShell 5.1 faz exatamente isso, e é o
  # cliente que se tem à mão numa máquina Windows. Dizer o óbvio custa quinze
  # caracteres e poupa uma investigação inteira.
  JSON_CONTENT_TYPE = 'application/json; charset=utf-8'
end
