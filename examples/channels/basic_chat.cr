require "../../src/hauyna-web-socket"

# Ejemplo básico de chat usando canales
router = Hauyna::WebSocket::Router.new

chat_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || "anonymous_#{Random::Secure.hex(8)}"
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    # Auto-suscripción al canal general
    Hauyna::WebSocket::Channel.subscribe("general", socket, identifier, {
      "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
    })
  }
)

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Chat básico iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 