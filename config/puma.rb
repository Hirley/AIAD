# frozen_string_literal: true

port ENV.fetch('PORT', 9292)
environment ENV.fetch('RACK_ENV', 'production')

threads Integer(ENV.fetch('PUMA_MIN_THREADS', 1)), Integer(ENV.fetch('PUMA_MAX_THREADS', 5))

# Um worker só, de propósito: o índice léxico BM25 vive na memória do processo.
# Com mais de um worker cada um teria o seu próprio índice e a busca híbrida
# passaria a depender de qual worker atendeu a requisição. Só suba esse número
# depois de trocar o Bm25Index por um índice compartilhado.
workers 0

preload_app!
