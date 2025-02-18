require "../src/hauyna-web-socket"
require "log"

# Configuramos el logging
Log.setup(:debug)

# Helper para imprimir
def imprimir(mensaje : String)
  STDOUT.puts(mensaje)
  STDOUT.flush
end

# Función para crear una tarea simple
def crear_tarea(id : Int32, tiempo : Int32) : JSON::Any
  {
    "id" => id,
    "tiempo" => tiempo,
    "timestamp" => Time.local.to_unix
  }.to_json.try { |json| JSON.parse(json) }
end

# Función para procesar una tarea
def procesar_tarea(tarea : JSON::Any)
  id = tarea["id"].as_i
  tiempo = tarea["tiempo"].as_i
  timestamp = Time.unix(tarea["timestamp"].as_i64)
  
  imprimir("  → Procesando tarea #{id} (#{tiempo}ms, creada: #{timestamp.to_s("%H:%M:%S")})")
  sleep(Time::Span.new(nanoseconds: tiempo * 1_000_000)) # ms a ns
  imprimir("  ✓ Tarea #{id} completada")
end

# Contador de tareas completadas
tareas_completadas = 0

# Configuramos los callbacks del procesador
config = Hauyna::WebSocket::BatchProcessing::Config.new(
  # Configuración básica
  batch_size: 2,              # Procesar de 2 en 2
  interval: 0.5,              # O cada 0.5 segundos
  max_queue_size: 5,          # Máximo 5 tareas en cola
  
  # Callback cuando inicia un lote
  on_batch_start: ->(size : Int32) {
    imprimir("\n=== Iniciando lote de #{size} tareas ===")
  },
  
  # Callback cuando termina un lote
  on_batch_complete: ->(size : Int32, errors : Int32) {
    imprimir("=== Lote completado: #{size} tareas (#{errors} errores) ===\n")
  },
  
  # Callback cuando la cola está llena
  on_queue_full: ->(size : Int32) {
    imprimir("!!! Cola llena (#{size} tareas) !!!")
  }
)

# Creamos el procesador
procesador = Hauyna::WebSocket::BatchProcessing::Processor.new(config)

# Lista de tiempos de procesamiento (en ms)
tiempos = [100, 150, 80, 200, 120]

imprimir("\nIniciando ejemplo básico de procesamiento...")
imprimir("-" * 50)

# Procesamos las tareas
tiempos.each_with_index do |tiempo, index|
  # Creamos y agregamos la tarea
  tarea = crear_tarea(index + 1, tiempo)
  imprimir("\nAgregando tarea #{index + 1} (#{tiempo}ms)")
  
  # Agregamos la tarea al procesador
  procesador.add(tarea) do |json_tarea|
    procesar_tarea(json_tarea)
    tareas_completadas += 1
  end
  
  # Pequeña pausa entre tareas
  sleep(Time::Span.new(nanoseconds: 300_000_000)) # 300ms
end

imprimir("\nEsperando que terminen las tareas...")
sleep(Time::Span.new(nanoseconds: 1_000_000_000)) # 1 segundo

# Detenemos el procesador
procesador.stop

imprimir("\nProcesamiento completado:")
imprimir("- Total de tareas completadas: #{tareas_completadas}")
imprimir("-" * 50) 