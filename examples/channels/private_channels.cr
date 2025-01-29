require "../../src/hauyna-web-socket"
require "http/server"
require "json"

# Ejemplo de canales privados
router = Hauyna::WebSocket::Router.new

private_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "Se requiere user_id"
  },

  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    case message["type"]?.try(&.as_s)
    when "create_private_room"
      if other_user = message["with_user"]?.try(&.as_s)
        # Crear canal privado
        room_id = "private_#{[identifier, other_user].sort.join("_")}"

        # Suscribir a ambos usuarios
        if other_socket = Hauyna::WebSocket::ConnectionManager.get_socket(other_user)
          Hauyna::WebSocket::Channel.subscribe(room_id, socket, identifier)
          Hauyna::WebSocket::Channel.subscribe(room_id, other_socket, other_user)

          # Notificar a ambos
          notification = {
            "type"         => JSON::Any.new("private_room_created"),
            "room_id"      => JSON::Any.new(room_id),
            "participants" => JSON::Any.new([identifier, other_user].to_json),
          }
          Hauyna::WebSocket::Channel.broadcast_to(room_id, notification)
        end
      end
    end
  }
)

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Chat privado iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
