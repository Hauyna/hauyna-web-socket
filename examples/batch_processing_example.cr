require "../src/hauyna-web-socket"
require "log"

# Configuramos el logging
Log.setup(:debug)

# Helper para imprimir con flush automático
def print_line(message : String)
  STDOUT.puts(message)
  STDOUT.flush
end

# Ejemplo de uso del sistema de procesamiento por lotes
module BatchProcessingExample
  # Error personalizado para mensajes
  class MessageError < Exception
    getter type : String
    getter details : String

    def initialize(@type : String, @details : String)
      super("Error de mensaje: #{@type} - #{@details}")
    end
  end

  # Simulamos un mensaje WebSocket
  class WebSocketMessage
    include JSON::Serializable
    
    property type : String
    property data : Hash(String, JSON::Any)
    
    def initialize(@type, @data)
    end
    
    def to_json_any : JSON::Any
      JSON.parse(self.to_json)
    end
  end
  
  # Clase para demostrar el uso del procesador por lotes
  class MessageProcessor
    @batch_processor : Hauyna::WebSocket::BatchProcessing::Processor
    @processed_messages = 0
    @total_errors = 0
    @start_time : Time::Span
    @error_types = Hash(String, Int32).new(0)
    
    def initialize
      print_line(">>> Iniciando procesador de mensajes...")
      
      # Configuramos el procesador por lotes
      config = Hauyna::WebSocket::BatchProcessing::Config.new(
        batch_size: 5,                    # Procesar en lotes de 5 mensajes
        interval: 0.5,                    # Procesar cada 0.5 segundos si no se llena el lote
        max_queue_size: 100,              # Máximo 100 mensajes en cola
        on_batch_start: ->(size : Int32) {
          print_line("\n[BATCH] Iniciando procesamiento de lote (tamaño: #{size})")
        },
        on_batch_complete: ->(size : Int32, errors : Int32) {
          print_line("[BATCH] Lote completado - Procesados: #{size}, Errores: #{errors}")
          print_line("-" * 50)
        },
        on_queue_full: ->(queue_size : Int32) {
          print_line("[ALERTA] Cola llena (tamaño máximo: #{queue_size})")
        },
        on_error: ->(error : Hauyna::WebSocket::BatchProcessing::BatchProcessorError) {
          print_line("[ERROR] #{error.message}")
          @total_errors += 1
          @error_types[error.type] += 1
        }
      )
      
      @batch_processor = Hauyna::WebSocket::BatchProcessing::Processor.new(config)
      @start_time = Time.monotonic
      print_line(">>> Procesador iniciado correctamente")
      print_line("-" * 50)
    end
    
    def process_message(message : WebSocketMessage)
      @batch_processor.add(message.to_json_any) do |json_message|
        handle_message(json_message)
      end
    rescue ex : MessageError
      @total_errors += 1
      @error_types[ex.type] += 1
      print_line("[ERROR] #{ex.message}")
    rescue ex : Exception
      @total_errors += 1
      @error_types["error_inesperado"] += 1
      print_line("[ERROR INESPERADO] #{ex.message}")
    end
    
    private def handle_message(json_message : JSON::Any)
      message = WebSocketMessage.from_json(json_message.to_json)
      
      case message.type
      when "chat"
        process_chat_message(message)
      when "notification"
        process_notification(message)
      when "error"
        print_line("[ERROR] Procesando mensaje de error...")
        raise MessageError.new("error_simulado", "Mensaje de error de prueba")
      when "unknown"
        print_line("[ALERTA] Tipo de mensaje desconocido: #{message.type}")
        @error_types["mensaje_desconocido"] += 1
      else
        print_line("[ERROR] Tipo de mensaje inválido: #{message.type}")
        raise MessageError.new("tipo_invalido", "Tipo de mensaje no soportado: #{message.type}")
      end
      
      @processed_messages += 1
    end
    
    private def process_chat_message(message : WebSocketMessage)
      print_line("[CHAT] Procesando mensaje: #{message.data["content"]}")
      print_line("       De usuario: #{message.data["user"]}")
      # Simulamos algún procesamiento
      sleep(Time::Span.new(nanoseconds: 100_000_000)) # 0.1 segundos
    end
    
    private def process_notification(message : WebSocketMessage)
      print_line("[NOTIFICACION] #{message.data["title"]}")
      print_line("              Prioridad: #{message.data["priority"]}")
      # Simulamos algún procesamiento
      sleep(Time::Span.new(nanoseconds: 50_000_000)) # 0.05 segundos
    end
    
    def stop
      @batch_processor.stop
      duration = Time.monotonic - @start_time
      
      print_line("\n" + "=" * 50)
      print_line("ESTADISTICAS FINALES")
      print_line("=" * 50)
      print_line("Tiempo total: #{duration.total_seconds.round(2)} segundos")
      print_line("Mensajes procesados: #{@processed_messages}")
      print_line("Total de errores: #{@total_errors}")
      
      if @total_errors > 0
        print_line("\nDesglose de errores:")
        @error_types.each do |tipo, cantidad|
          print_line("  - #{tipo}: #{cantidad}")
        end
      end
      
      print_line("=" * 50)
    end
  end
end

# Ejecutamos el ejemplo
print_line("\nINICIANDO EJEMPLO DE PROCESAMIENTO POR LOTES")
print_line("=" * 50)

processor = BatchProcessingExample::MessageProcessor.new

# Generamos algunos mensajes de ejemplo
messages = [
  BatchProcessingExample::WebSocketMessage.new(
    "chat",
    {"content" => JSON::Any.new("¡Hola a todos!"), "user" => JSON::Any.new("Usuario1")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "notification",
    {"title" => JSON::Any.new("Nueva actualización"), "priority" => JSON::Any.new("high")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "chat",
    {"content" => JSON::Any.new("¿Cómo están?"), "user" => JSON::Any.new("Usuario2")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "error",
    {"message" => JSON::Any.new("Este mensaje generará un error")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "notification",
    {"title" => JSON::Any.new("Mantenimiento programado"), "priority" => JSON::Any.new("low")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "chat",
    {"content" => JSON::Any.new("¡Hasta luego!"), "user" => JSON::Any.new("Usuario1")}
  ),
  BatchProcessingExample::WebSocketMessage.new(
    "unknown",
    {"data" => JSON::Any.new("Tipo desconocido")}
  )
]

print_line("\nProcesando #{messages.size} mensajes de prueba...")
print_line("-" * 50)

messages.each_with_index do |message, index|
  print_line("\nEnviando mensaje #{index + 1}/#{messages.size}...")
  processor.process_message(message)
  # Pequeña pausa para simular mensajes llegando en diferentes momentos
  sleep(Time::Span.new(nanoseconds: 200_000_000)) # 0.2 segundos
end

print_line("\nEsperando que se procesen los últimos mensajes...")
sleep(Time::Span.new(nanoseconds: 1_000_000_000)) # 1 segundo

# Detenemos el procesador y mostramos estadísticas
processor.stop 