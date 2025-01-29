require "../../src/hauyna-web-socket"

# Ejemplo de chat con múltiples salas
router = Hauyna::WebSocket::Router.new

multi_room_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || "anonymous_#{Random::Secure.hex(8)}"
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    case message["type"]?.try(&.as_s)
    when "join_room"
      if room = message["room"]?.try(&.as_s)
        # Unirse a una sala
        Hauyna::WebSocket::Channel.subscribe(room, socket, identifier, {
          "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
        })

        # Notificar a la sala
        Hauyna::WebSocket::Channel.broadcast_to(room, {
          "type" => JSON::Any.new("system"),
          "message" => JSON::Any.new("#{identifier} se unió a la sala")
        })

        # Enviar lista de usuarios en la sala
        subscribers = Hauyna::WebSocket::Channel.subscribers(room)
        socket.send({
          "type" => JSON::Any.new("room_users"),
          "room" => JSON::Any.new(room),
          "users" => JSON::Any.new(subscribers.to_json)
        }.to_json)
      end
    end
  }
)

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Chat multi-sala iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 