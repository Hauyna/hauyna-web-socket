require "../../src/hauyna-web-socket"

# Ejemplo de uso de metadatos en canales
router = Hauyna::WebSocket::Router.new

metadata_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "Se requiere user_id"
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    return unless identifier

    case message["type"]?.try(&.as_s)
    when "join_with_role"
      if channel = message["channel"]?.try(&.as_s)
        role = message["role"]?.try(&.as_s) || "user"
        
        # Suscribir con metadata
        Hauyna::WebSocket::Channel.subscribe(channel, socket, identifier, {
          "role" => JSON::Any.new(role),
          "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
        })

        # Verificar metadata
        if metadata = Hauyna::WebSocket::Channel.get_subscription_metadata(channel, socket)
          puts "Usuario #{identifier} se unió como #{metadata["role"]?}"
        end
      end
    end
  }
)

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Ejemplo de metadatos iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 