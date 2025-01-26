require "json"
require "uri"
require "http"

require "../src/hauyna-web-socket"

# Definición del Handler con manejo de parámetros y patrones de mensajería
chat_handler = Hauyna::WebSocket::Handler.new(
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Conexión abierta con parámetros: #{params}"
    # Implementa lógica adicional de autenticación o inicialización aquí si es necesario
  },
  on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
    puts "Mensaje recibido: #{data}"

    begin
      action = data["event"]?.try(&.as_s)

      case action
      when "broadcast"
        content = data["content"]?.try(&.as_s)
        if content
          Hauyna::WebSocket::Events.broadcast(content)
        end
      when "send_to_one"
        identifier = data["recipient_id"]?.try(&.as_s)
        content = data["content"]?.try(&.as_s)
        if identifier && content
          Hauyna::WebSocket::Events.send_to_one(identifier, content)
        end
      when "send_to_many"
        identifiers = data["recipient_ids"]?.try(&.as_a).try(&.map(&.as_s))
        content = data["content"]?.try(&.as_s)
        if identifiers && content
          Hauyna::WebSocket::Events.send_to_many(identifiers, content)
        end
      when "join_group"
        group_name = data["group"]?.try(&.as_s)
        if group_name
          identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
          if identifier
            Hauyna::WebSocket::ConnectionManager.add_to_group(identifier, group_name)
            socket.send(JSON.build { |json|
              json.object do
                json.field "event", "group_joined"
                json.field "data", "Te has unido al grupo #{group_name}."
              end
            })
          else
            socket.send(JSON.build { |json|
              json.object do
                json.field "event", "error"
                json.field "data", "No se pudo identificar tu conexión."
              end
            })
          end
        end
      when "leave_group"
        group_name = data["group"]?.try(&.as_s)
        if group_name
          identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
          if identifier
            Hauyna::WebSocket::ConnectionManager.remove_from_group(identifier, group_name)
            socket.send(JSON.build { |json|
              json.object do
                json.field "event", "group_left"
                json.field "data", "Has salido del grupo #{group_name}."
              end
            })
          else
            socket.send(JSON.build { |json|
              json.object do
                json.field "event", "error"
                json.field "data", "No se pudo identificar tu conexión."
              end
            })
          end
        end
      when "send_to_group"
        group_name = data["group"]?.try(&.as_s)
        content = data["content"]?.try(&.as_s)
        if group_name && content
          Hauyna::WebSocket::Events.send_to_group(group_name, content)
        end
      else
        socket.send(JSON.build { |json|
          json.object do
            json.field "event", "error"
            json.field "data", "Acción desconocida o parámetros inválidos."
          end
        })
      end
    rescue e : Exception
      socket.send(JSON.build { |json|
        json.object do
          json.field "event", "error"
          json.field "data", "Error al procesar el mensaje: #{e.message}"
        end
      })
    end
  },
  on_close: ->(socket : HTTP::WebSocket) {
    puts "Conexión cerrada"
    # Implementa lógica de limpieza o notificación aquí si es necesario
  },
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String? {
    # Devolvemos el identificador como String?
    params["client_id"]?.try(&.as_s) || params["session_id"]?.try(&.as_s)
  }
)

# Configuración del Router
router = Hauyna::WebSocket::Router.new
router.websocket("/chat", chat_handler)

# Registro de Eventos
Hauyna::WebSocket::Events.on("broadcast") do |socket, data|
  if content = data["content"]?.try(&.as_s)
    Hauyna::WebSocket::ConnectionManager.broadcast(content)
  end
end

Hauyna::WebSocket::Events.on("send_to_one") do |socket, data|
  identifier = data["recipient_id"]?.try(&.as_s)
  content = data["content"]?.try(&.as_s)
  if identifier && content
    Hauyna::WebSocket::ConnectionManager.send_to_one(identifier, content)
  end
end

Hauyna::WebSocket::Events.on("send_to_many") do |socket, data|
  if recipient_ids = data["recipient_ids"]?.try(&.as_a)
    identifiers = recipient_ids.compact_map(&.as_s)
    if content = data["content"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.send_to_many(identifiers, content)
    end
  end
end

Hauyna::WebSocket::Events.on("send_to_group") do |socket, data|
  group_name = data["group"]?.try(&.as_s)
  content = data["content"]?.try(&.as_s)
  if group_name && content
    Hauyna::WebSocket::ConnectionManager.send_to_group(group_name, content)
  end
end

# Inicialización del servidor HTTP con el Router
server = HTTP::Server.new do |context|
  unless router.call(context)
    context.response.status_code = 404
    context.response.print "Not Found"
  end
end

# Ejecutar el servidor en el puerto 3000
puts "Servidor WebSocket iniciado en ws://0.0.0.0:3000/chat"
server.listen("0.0.0.0", 3000)
