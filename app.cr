require "./src/hauyna-web-socket"
require "log"

# Configuración del procesamiento por lotes
batch_config = Hauyna::WebSocket::BatchProcessing::Config.new(
  batch_size: 100,                   # Procesar cada 100 mensajes
  interval: 0.5,                     # O cada 0.5 segundos
  processor: ->(message : JSON::Any) {
    # Procesar según el tipo de mensaje
    case message["type"]?.try(&.as_s)
    when "chat"
      Log.info { "💬 Chat: #{message["content"]}" }
    when "notification"
      Log.info { "🔔 Notificación: #{message["content"]}" }
    when "update"
      Log.info { "🔄 Actualización: #{message["content"]}" }
    else
      Log.warn { "Tipo de mensaje desconocido: #{message}" }
    end
    message  # Retornamos el mensaje procesado
  },
  on_batch_start: ->(size : Int32) {
    Log.info { "⚡ Iniciando lote de #{size} operaciones" }
  },
  on_batch_complete: ->(total : Int32, errors : Int32) {
    Log.info { "✅ Lote completado - Procesadas: #{total}, Errores: #{errors}" }
  }
)

# Crear el procesador por lotes
batch_processor = Hauyna::WebSocket::BatchProcessing::Processor.new(batch_config)

# Crear el handler con procesamiento por lotes
handler = Hauyna::WebSocket::Handler.new(
  batch_processor: batch_processor,   # Procesador de lotes
  heartbeat_interval: 30.seconds,    # Intervalo de heartbeat
  
  # Callback para conexión establecida
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    Log.info { "🔌 Nueva conexión establecida" }
  },
  
  # Callback para desconexión
  on_close: ->(socket : HTTP::WebSocket) {
    Log.info { "🔌 Conexión cerrada" }
  }
)