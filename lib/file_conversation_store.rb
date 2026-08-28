# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'

# Guarda a conversa em disco, um JSON por conversa. Cumpre o mesmo contrato do
# `ConversationStore`, então é troca direta — e é o que faz o histórico
# sobreviver ao processo morrer.
#
# Duas decisões que definem o comportamento:
#
# - **O nome do arquivo é higienizado e ainda leva um digest.** O id vem de
#   fora (id de sessão de quem chama a API): sem higienizar, um id com "../"
#   escreveria fora do diretório. Só higienizar, porém, colide — "a/b" e "a-b"
#   viram o mesmo nome e uma conversa sobrescreveria a outra. O prefixo legível
#   é para o humano que abre a pasta; o digest é o que identifica de verdade.
# - **JSON não tem símbolo.** A leitura converte as chaves de volta, senão o
#   comportamento mudaria depois do primeiro reinício — o pior momento para
#   descobrir.
class FileConversationStore
  PREFIX_LENGTH = 40
  DIGEST_LENGTH = 12

  def initialize(directory)
    @directory = directory
    FileUtils.mkdir_p(@directory)
  end

  def load(id)
    path = path_for(id)
    return [] unless File.exist?(path)

    JSON.parse(File.read(path), symbolize_names: true)
  end

  def save(id, turns)
    File.write(path_for(id), JSON.generate(turns))
  end

  def clear(id)
    FileUtils.rm_f(path_for(id))
  end

  private

  def path_for(id)
    File.join(@directory, filename(id))
  end

  def filename(id)
    value = id.to_s
    prefix = value.gsub(/[^\w-]/, '_')[0, PREFIX_LENGTH]

    "#{prefix}-#{Digest::SHA256.hexdigest(value)[0, DIGEST_LENGTH]}.json"
  end
end
