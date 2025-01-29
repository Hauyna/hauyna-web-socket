# Sistema de Notificaciones con Hauyna WebSocket

## Implementación Básica

```crystal
notification_handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "User ID required"
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    identifier = params["user_id"]?.try(&.as_s)
    return unless identifier
    
    # Suscribir al canal personal de notificaciones
    Hauyna::WebSocket::Channel.subscribe(
      "notifications:#{identifier}", 
      socket, 
      identifier
    )
  }
)
```

## Envío de Notificaciones

```crystal
def send_notification(user_id : String, notification : Hash)
  Hauyna::WebSocket::Channel.broadcast_to(
    "notifications:#{user_id}",
    notification.to_json
  )
end
```

## Cliente JavaScript

```javascript
const ws = new WebSocket('ws://localhost:8080/notifications?user_id=123');

ws.onmessage = (event) => {
  const notification = JSON.parse(event.data);
  showNotification(notification);
};
``` 