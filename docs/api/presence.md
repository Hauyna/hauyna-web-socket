# Presence API

El sistema de Presence maneja el seguimiento en tiempo real de usuarios.

## Métodos Principales

### track
```crystal
def self.track(identifier : String, metadata : Hash(String, JSON::Any))
```
Registra la presencia de un usuario con sus metadatos asociados.

### update
```crystal
def self.update(
  identifier : String, 
  metadata : Hash(String, JSON::Any)
)
```
Actualiza los metadatos de presencia.

### untrack
```crystal
def self.untrack(identifier : String)
```
Elimina el seguimiento de presencia de un usuario.

### list_by
```crystal
def self.list_by(
  criteria : Hash(String, String)
) : Hash(String, Hash(String, JSON::Any))
```
Lista usuarios según criterios.

### list_by_channel
```crystal
def self.list_by_channel(channel : String) : Hash(String, Hash(String, JSON::Any))
```
Lista los usuarios presentes en un canal específico.

## Ejemplos

```crystal
# Registrar presencia
Presence.track("user_123", {
  "status" => JSON::Any.new("online"),
  "last_seen" => JSON::Any.new(Time.local.to_s)
})

# Actualizar estado
Presence.update("user_123", {
  "status" => JSON::Any.new("away"),
  "last_activity" => JSON::Any.new(Time.local.to_s)
})

# Listar usuarios online
online_users = Presence.list_by({"status" => "online"})

# Listar usuarios en un canal
channel_users = Presence.list_by_channel("chat_room_1")

# Eliminar seguimiento
Presence.untrack("user_123")
``` 