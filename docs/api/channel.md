# Channel API

El módulo Channel maneja la comunicación en tiempo real a través de canales de suscripción.

## Métodos Públicos

### subscribe
```crystal
def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
```
Suscribe un socket a un canal específico.

**Parámetros:**
- `channel`: Nombre del canal
- `socket`: Conexión WebSocket
- `identifier`: Identificador único del usuario
- `metadata`: Metadatos adicionales (opcional)

### unsubscribe
```crystal
def self.unsubscribe(channel : String, socket : HTTP::WebSocket)
```
Desuscribe un socket de un canal.

### broadcast_to
```crystal
def self.broadcast_to(channel : String, message : Hash(String, JSON::Any) | String)
```
Envía un mensaje a todos los suscriptores de un canal.

### subscription_count
```crystal
def self.subscription_count(channel : String) : Int32
```
Retorna el número de suscriptores en un canal.

### subscribers
```crystal
def self.subscribers(channel : String) : Array(String)
```
Retorna los identificadores de los suscriptores de un canal.

### subscribed?
```crystal
def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
```
Verifica si un socket está suscrito a un canal.

### get_subscription_metadata
```crystal
def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
```
Obtiene los metadatos de una suscripción.

### presence_data
```crystal
def self.presence_data(channel : String) : Hash(String, JSON::Any)
```
Obtiene datos de presencia para un canal.

### handle_reconnection
```crystal
def self.handle_reconnection(socket : HTTP::WebSocket, old_socket : HTTP::WebSocket)
```
Maneja la reconexión de un socket, transfiriendo sus suscripciones.

### cleanup_socket
```crystal
def self.cleanup_socket(socket : HTTP::WebSocket)
```
Limpia todas las suscripciones asociadas a un socket.

## Ejemplos de Uso

```crystal
# Suscribir a un canal con metadatos
Channel.subscribe("chat", socket, "user_123", {
  "role" => JSON::Any.new("user"),
  "name" => JSON::Any.new("John Doe")
})

# Verificar suscripción
if Channel.subscribed?("chat", socket)
  puts "Usuario suscrito al chat"
end

# Obtener metadatos
if metadata = Channel.get_subscription_metadata("chat", socket)
  puts "Rol del usuario: #{metadata["role"]}"
end

# Broadcast a canal
Channel.broadcast_to("chat", {
  "type" => JSON::Any.new("message"),
  "content" => JSON::Any.new("Hola mundo"),
  "sender" => JSON::Any.new("user_123")
})

# Obtener estadísticas
puts "Usuarios en el chat: #{Channel.subscription_count("chat")}"
puts "Lista de usuarios: #{Channel.subscribers("chat").join(", ")}"
```

## Manejo de Reconexiones

```crystal
# Manejar reconexión de usuario
Channel.handle_reconnection(new_socket, old_socket)
```

## Limpieza de Recursos

```crystal
# Limpiar suscripciones al cerrar
Channel.cleanup_socket(socket)
``` 