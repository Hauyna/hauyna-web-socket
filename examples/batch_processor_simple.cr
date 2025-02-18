require "../src/hauyna-web-socket"
require "log"

# Configuramos el logging
Log.setup(:debug)

# Helper para imprimir con flush automático
def print_line(message : String)
  STDOUT.puts(message)
  STDOUT.flush
end

# Ejemplo simple de procesamiento por lotes
module SimpleBatchExample
  # Una clase simple para representar una tarea
  class Task
    include JSON::Serializable
    
    property nombre : String
    property duracion : Int32
    
    def initialize(@nombre : String, @duracion : Int32)
    end
    
    def to_json_any : JSON::Any
      JSON.parse(self.to_json)
    end
  end
  
  # Procesador simple de tareas
  class SimpleProcessor
    @batch_processor : Hauyna::WebSocket::BatchProcessing::Processor
    @tareas_completadas = 0
    
    def initialize
      print_line("Iniciando procesador simple de tareas...")
      
      # Configuración básica del procesador
      config = Hauyna::WebSocket::BatchProcessing::Config.new(
        batch_size: 3,              # Procesar en lotes de 3 tareas
        interval: 1.0,              # O cada 1 segundo
        max_queue_size: 10,         # Máximo 10 tareas en cola
        on_batch_start: ->(size : Int32) {
          print_line("\n>>> Iniciando procesamiento de #{size} tareas...")
        },
        on_batch_complete: ->(size : Int32, errors : Int32) {
          print_line(">>> Completadas #{size} tareas (#{errors} errores)")
          print_line("-" * 40)
        }
      )
      
      @batch_processor = Hauyna::WebSocket::BatchProcessing::Processor.new(config)
      print_line("Procesador listo!")
      print_line("-" * 40)
    end
    
    # Método para agregar una tarea
    def agregar_tarea(tarea : Task)
      print_line("Agregando tarea: #{tarea.nombre} (#{tarea.duracion} ms)")
      
      @batch_processor.add(tarea.to_json_any) do |json_tarea|
        procesar_tarea(json_tarea)
      end
    end
    
    private def procesar_tarea(json_tarea : JSON::Any)
      tarea = Task.from_json(json_tarea.to_json)
      
      # Simulamos el procesamiento
      print_line("  → Procesando: #{tarea.nombre}")
      sleep(Time::Span.new(nanoseconds: tarea.duracion * 1_000_000)) # Convertimos ms a ns
      
      @tareas_completadas += 1
      print_line("  ✓ Completada: #{tarea.nombre}")
    end
    
    def detener
      @batch_processor.stop
      print_line("\nResumen:")
      print_line("- Tareas completadas: #{@tareas_completadas}")
    end
  end
end

# Creamos algunas tareas de ejemplo
tareas = [
  SimpleBatchExample::Task.new("Tarea A", 100),  # 100ms
  SimpleBatchExample::Task.new("Tarea B", 150),  # 150ms
  SimpleBatchExample::Task.new("Tarea C", 80),   # 80ms
  SimpleBatchExample::Task.new("Tarea D", 200),  # 200ms
  SimpleBatchExample::Task.new("Tarea E", 120),  # 120ms
  SimpleBatchExample::Task.new("Tarea F", 90),   # 90ms
  SimpleBatchExample::Task.new("Tarea G", 180)   # 180ms
]

# Creamos el procesador
procesador = SimpleBatchExample::SimpleProcessor.new

# Procesamos las tareas
print_line("\nIniciando procesamiento de #{tareas.size} tareas...")
print_line("-" * 40)

tareas.each do |tarea|
  procesador.agregar_tarea(tarea)
  # Pequeña pausa entre tareas
  sleep(Time::Span.new(nanoseconds: 500_000_000)) # 500ms
end

# Esperamos que se completen las últimas tareas
print_line("\nEsperando que se completen las últimas tareas...")
sleep(Time::Span.new(nanoseconds: 2_000_000_000)) # 2 segundos

# Detenemos el procesador
procesador.detener 