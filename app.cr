require "./src/hauyna-web-socket"

# Crear el router
router = Hauyna::WebSocket::Router.new

# Configurar el handler con todas las funcionalidades de Channel
chat_handler = Hauyna::WebSocket::Handler.new(
  # Extraer identificador del usuario
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || "anonymous_#{Random::Secure.hex(8)}"
  },

  # Manejar conexión nueva
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    # Suscribir al canal general automáticamente
    Hauyna::WebSocket::Channel.subscribe("general", socket, identifier, {
      "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
      "role" => JSON::Any.new("user")
    })

    # Notificar a todos de la nueva conexión
    welcome_message = {
      "type" => JSON::Any.new("system"),
      "event" => JSON::Any.new("user_joined"),
      "user" => JSON::Any.new(identifier),
      "timestamp" => JSON::Any.new(Time.local.to_unix_ms.to_s)
    }
    Hauyna::WebSocket::Channel.broadcast_to("general", welcome_message)

    # Registrar presencia
    Hauyna::WebSocket::Presence.track(identifier, {
      "status" => JSON::Any.new("online"),
      "channel" => JSON::Any.new("general"),
      "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
    })
  },

  # Manejar mensajes
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    case message["type"]?.try(&.as_s)
    # Manejo de suscripción a canales
    when "subscribe_channel"
      if channel = message["channel"]?.try(&.as_s)
        metadata = message["metadata"]?.try(&.as_h) || {} of String => JSON::Any
        Hauyna::WebSocket::Channel.subscribe(channel, socket, identifier, metadata)
        
        # Notificar número de suscriptores
        count = Hauyna::WebSocket::Channel.subscription_count(channel)
        status_message = {
          "type" => JSON::Any.new("channel_status"),
          "channel" => JSON::Any.new(channel),
          "subscribers" => JSON::Any.new(count.to_i64)
        }
        socket.send(status_message.to_json)
      end

    # Manejo de desuscripción de canales
    when "unsubscribe_channel"
      if channel = message["channel"]?.try(&.as_s)
        Hauyna::WebSocket::Channel.unsubscribe(channel, socket)
      end

    # Manejo de mensajes en canales
    when "channel_message"
      if channel = message["channel"]?.try(&.as_s)
        if content = message["content"]?
          # Verificar suscripción al canal
          if Hauyna::WebSocket::Channel.subscribed?(channel, socket)
            # Obtener metadata de la suscripción
            metadata = Hauyna::WebSocket::Channel.get_subscription_metadata(channel, socket)
            
            message_data = {
              "type" => JSON::Any.new("message"),
              "channel" => JSON::Any.new(channel),
              "user" => JSON::Any.new(identifier),
              "content" => content,
              "metadata" => JSON::Any.new(metadata.try(&.to_json) || "{}"),
              "timestamp" => JSON::Any.new(Time.local.to_unix_ms.to_s)
            }
            Hauyna::WebSocket::Channel.broadcast_to(channel, message_data)
          end
        end
      end

    # Listar canales suscritos
    when "list_subscriptions"
      channels = Hauyna::WebSocket::Channel.subscribed_channels(socket)
      response = {
        "type" => JSON::Any.new("subscriptions_list"),
        "channels" => JSON::Any.new(channels.to_json)
      }
      socket.send(response.to_json)

    # Obtener datos de presencia de un canal
    when "get_presence"
      if channel = message["channel"]?.try(&.as_s)
        presence_data = Hauyna::WebSocket::Channel.presence_data(channel)
        response = {
          "type" => JSON::Any.new("presence_data"),
          "channel" => JSON::Any.new(channel),
          "users" => JSON::Any.new(presence_data.to_json)
        }
        socket.send(response.to_json)
      end
    end
  },

  # Manejar cierre de conexión
  on_close: ->(socket : HTTP::WebSocket) {
    if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      # Obtener canales suscritos antes de limpiar
      channels = Hauyna::WebSocket::Channel.subscribed_channels(socket)
      
      # Limpiar suscripciones
      Hauyna::WebSocket::Channel.cleanup_socket(socket)

      # Notificar a cada canal
      channels.each do |channel|
        leave_message = {
          "type" => JSON::Any.new("system"),
          "event" => JSON::Any.new("user_left"),
          "channel" => JSON::Any.new(channel),
          "user" => JSON::Any.new(identifier),
          "timestamp" => JSON::Any.new(Time.local.to_unix_ms.to_s)
        }
        Hauyna::WebSocket::Channel.broadcast_to(channel, leave_message)
      end
    end
  },

  # Configurar heartbeat
  heartbeat_interval: 30.seconds
)

# Registrar la ruta WebSocket
router.websocket "/chat", chat_handler

# Iniciar el servidor
server = HTTP::Server.new do |context|
  if router.call(context)
    # WebSocket manejado
  else
    context.response.status_code = 404
    context.response.print "Not Found"
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
