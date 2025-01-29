# Sistema de Presencia con Hauyna WebSocket

## Implementación Básica

```crystal
presence_handler = Hauyna::WebSocket::Handler.new(
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = params["user_id"]?.try(&.as_s)
    return unless identifier

    # Registrar presencia
    Hauyna::WebSocket::Presence.track(identifier, {
      "status" => JSON::Any.new("online"),
      "last_seen" => JSON::Any.new(Time.local.to_s)
    })
  },
  
  on_close: ->(socket : HTTP::WebSocket) {
    if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      Hauyna::WebSocket::Presence.untrack(identifier)
    end
  }
)
```

## Estados Personalizados

```crystal
# Actualizar estado
Hauyna::WebSocket::Presence.update(user_id, {
  "status" => JSON::Any.new("away"),
  "activity" => JSON::Any.new("in_meeting"),
  "last_activity" => JSON::Any.new(Time.local.to_s)
})

# Consultar usuarios
online_users = Hauyna::WebSocket::Presence.list_by({
  "status" => "online"
})
``` 