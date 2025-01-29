# Presence API

El sistema de Presence maneja el seguimiento en tiempo real de usuarios.

## Métodos Principales

### track
```crystal
def self.track(
  identifier : String, 
  metadata : Hash(String, JSON::Any)
)
```
Registra la presencia de un usuario.

### update
```crystal
def self.update(
  identifier : String, 
  metadata : Hash(String, JSON::Any)
)
```
Actualiza los metadatos de presencia.

### list_by
```crystal
def self.list_by(
  criteria : Hash(String, String)
) : Hash(String, Hash(String, JSON::Any))
```
Lista usuarios según criterios.

## Ejemplos

```crystal
# Registrar presencia
Presence.track("user_123", {
  "status" => JSON::Any.new("online"),
  "last_seen" => JSON::Any.new(Time.local.to_s)
})

# Listar usuarios online
online_users = Presence.list_by({"status" => "online"})
``` 