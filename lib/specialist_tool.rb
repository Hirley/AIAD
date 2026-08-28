# frozen_string_literal: true

require_relative 'tool'

# Embrulha um agente inteiro como ferramenta, para o time multi-agente poder
# tratar especialista e ferramenta do mesmo jeito.
#
# O ganho de reaproveitar `Tool` aqui não é economia de linhas: é que o
# catálogo que o roteador lê, a validação de argumentos e a conversão de falha
# em texto já existem e já são testados. Especialista que estoura vira texto de
# erro em vez de derrubar o time, sem nenhum código novo.
#
# O agente pode terminar sem concluir. Isso vem escrito na resposta: quem
# revisa precisa saber a diferença entre "respondeu" e "desistiu no meio".
module SpecialistTool
  PARAMETERS = { tarefa: 'o que este especialista deve resolver' }.freeze
  UNFINISHED_MARK = '(não concluído)'

  def self.build(name:, description:, agent:)
    Tool.new(name: name, description: description, parameters: PARAMETERS) do |arguments|
      result = agent.run(arguments[:tarefa].to_s)

      answer_for(result)
    end
  end

  def self.answer_for(result)
    answer = result[:answer].to_s
    return answer if result[:finished]

    "#{UNFINISHED_MARK} #{answer}"
  end
end
