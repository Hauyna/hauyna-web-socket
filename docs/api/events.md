# Events API

El módulo Events maneja el sistema de eventos y broadcasting.

## Métodos Principales

### on
```crystal
def self.on(event : String, &block : EventCallback)
```
Registra un manejador para un tipo de evento específico.

### trigger_event
```crystal
def self.trigger_event(event : String, socket : HTTP::WebSocket, data : Hash(String, JSON::Any))
```
Dispara un evento específico con datos asociados.

### broadcast
```crystal
def self.broadcast(content : String)
```
Envía un mensaje a todas las conexiones.

### send_to_one
```crystal
def self.send_to_one(identifier : String, content : String)
```
Envía un mensaje a un usuario específico.

### send_to_many
```crystal
def self.send_to_many(identifiers : Array(String), content : String)
```
Envía un mensaje a múltiples usuarios.

### send_to_group
```crystal
def self.send_to_group(group_name : String, content : String)
```
Envía un mensaje a todos los miembros de un grupo.

## Ejemplos

```crystal
# Registrar manejador de evento
Events.on("user_joined") do |socket, data|
  puts "Usuario #{data["user_id"]} se unió"
end

# Enviar broadcast
Events.broadcast({
  type: "announcement",
  message: "Servidor reiniciando en 5 minutos"
}.to_json)

# Enviar mensaje directo
Events.send_to_one("user_123", "Mensaje privado")

# Enviar a grupo
Events.send_to_group("admins", "Notificación administrativa")
``` 