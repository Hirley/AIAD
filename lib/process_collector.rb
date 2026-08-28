# frozen_string_literal: true

# Métricas do processo: memória residente, CPU acumulada, threads vivas e há
# quanto tempo está no ar.
#
# Quatro decisões definem o comportamento:
#
# - **Tudo amostrado no scrape, nada acumulado.** Não faz sentido guardar um
#   histórico de memória aqui dentro: quem guarda série temporal é o Prometheus,
#   e o valor certo é o que o sistema diz no instante da coleta.
# - **CPU vem do relógio do próprio Ruby**, não do `/proc`. O
#   `CLOCK_PROCESS_CPUTIME_ID` é portátil e já vem em segundos, que é a unidade
#   que o Prometheus espera para tempo.
# - **Memória vem do `/proc`, e só existe onde o `/proc` existe.** O container é
#   Linux, mas a suíte roda na máquina de quem estiver desenvolvendo. Sem
#   `/proc`, a métrica simplesmente não é declarada.
# - **Métrica ausente é melhor que métrica mentindo.** Publicar memória zero
#   onde não dá para medir faria o painel mostrar um serviço leve e saudável
#   justamente onde não se sabe nada. "Sem dados" é a informação verdadeira.
class ProcessCollector
  STATUS_PATH = '/proc/self/status'
  RSS_LINE = /^VmRSS:\s+(\d+)\s+kB/
  BYTES_PER_KB = 1024

  CPU_SECONDS = -> { Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) }
  MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(status_path: STATUS_PATH, cpu: CPU_SECONDS, clock: MONOTONIC, threads: -> { Thread.list.size })
    @status_path = status_path
    @cpu = cpu
    @clock = clock
    @threads = threads
    @started_at = clock.call
  end

  def install(registry)
    collector = self

    registry.counter('aiad_process_cpu_seconds_total', help: 'Tempo de CPU consumido pelo processo.') do
      collector.cpu_seconds
    end
    registry.gauge('aiad_process_uptime_seconds', help: 'Tempo desde a subida do processo.') do
      collector.uptime
    end
    registry.gauge('aiad_process_threads', help: 'Threads vivas no processo.') { collector.threads }

    install_memory(registry, collector)
  end

  def cpu_seconds
    @cpu.call
  end

  def uptime
    @clock.call - @started_at
  end

  def threads
    @threads.call
  end

  # Nil, e não zero, quando não dá para ler: quem chama decide o que fazer com
  # a ausência, e aqui a decisão é não declarar a métrica.
  def resident_memory_bytes
    line = File.foreach(@status_path).find { |candidate| RSS_LINE.match?(candidate) }

    line && (Integer(RSS_LINE.match(line)[1]) * BYTES_PER_KB)
  rescue SystemCallError
    nil
  end

  def memory_readable?
    !resident_memory_bytes.nil?
  end

  private

  def install_memory(registry, collector)
    return unless memory_readable?

    registry.gauge('aiad_process_resident_memory_bytes', help: 'Memória residente do processo.') do
      collector.resident_memory_bytes
    end
  end
end
