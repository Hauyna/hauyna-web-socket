require "../../src/hauyna-web-socket"

# Ejemplo de chat con sistema de presencia
router = Hauyna::WebSocket::Router.new

presence_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "Se requiere user_id"
  },

  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    # Registrar presencia
    Hauyna::WebSocket::Presence.track(identifier, {
      "status"    => JSON::Any.new("online"),
      "last_seen" => JSON::Any.new(Time.local.to_unix_ms.to_s),
    })

    # Obtener lista de usuarios presentes
    presence_data = Hauyna::WebSocket::Channel.presence_data("general")
    socket.send({
      "type"  => "presence_list",
      "users" => presence_data,
    }.to_json)
  }
)

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Chat con presencia iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
