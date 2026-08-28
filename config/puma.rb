# frozen_string_literal: true

port ENV.fetch('PORT', 9292)
environment ENV.fetch('RACK_ENV', 'production')

threads Integer(ENV.fetch('PUMA_MIN_THREADS', 1)), Integer(ENV.fetch('PUMA_MAX_THREADS', 5))

# Um worker só, de propósito: o estado que a busca híbrida usa vive na memória
# do processo — o índice léxico BM25, o ParentStore e o cache semântico. Com
# mais de um worker cada um teria a sua cópia, e a resposta passaria a depender
# de qual deles atendeu a requisição. O BM25 é o que trava de verdade, porque
# muda o resultado da busca em silêncio: só suba esse número depois de trocá-lo
# por um índice compartilhado.
workers 0

preload_app!
