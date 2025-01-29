# Chat en Tiempo Real con Hauyna WebSocket

## Implementación Básica

```crystal
require "hauyna-web-socket"

# Configurar el handler
chat_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "User ID required"
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = params["user_id"]?.try(&.as_s)
    return unless identifier

    # Registrar presencia
    Hauyna::WebSocket::Presence.track(identifier, {
      "status" => JSON::Any.new("online"),
      "joined_at" => JSON::Any.new(Time.local.to_s)
    })

    # Suscribir al canal general
    Hauyna::WebSocket::Channel.subscribe("general", socket, identifier)
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    case message["type"]?.try(&.as_s)
    when "chat_message"
      handle_chat_message(socket, message)
    when "status_update" 
      handle_status_update(socket, message)
    end
  }
)

# Iniciar servidor
server = HTTP::Server.new do |context|
  # ... configuración del servidor
end
```

## Cliente JavaScript

```javascript
const ws = new WebSocket('ws://localhost:8080/chat?user_id=123');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  // Manejar mensaje...
};
```

## Características Avanzadas

- Salas privadas
- Mensajes directos
- Historial de mensajes
- Indicador de escritura 