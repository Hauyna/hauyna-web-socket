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
def self.trigger_event(
  event : String, 
  socket : HTTP::WebSocket, 
  data : Hash(String, JSON::Any)
)
```
Dispara un evento específico.

### broadcast
```crystal
def self.broadcast(content : String)
```
Envía un mensaje a todas las conexiones.

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
``` 