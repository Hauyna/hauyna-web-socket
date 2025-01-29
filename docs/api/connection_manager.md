# Connection Manager API

El ConnectionManager gestiona las conexiones WebSocket, sus estados y grupos.

## Estados de Conexión

```crystal
enum ConnectionState
  Connected    # Socket conectado y funcionando
  Disconnected # Socket desconectado
  Reconnecting # En proceso de reconexión
  Error        # Estado de error
  Idle         # Sin actividad reciente
end
```

## Métodos Principales

### register
```crystal
def self.register(socket : HTTP::WebSocket, identifier : String)
```
Registra una nueva conexión WebSocket.

**Parámetros:**
- `socket`: Conexión WebSocket a registrar
- `identifier`: Identificador único del usuario

### unregister
```crystal
def self.unregister(socket : HTTP::WebSocket)
```
Elimina el registro de una conexión.

### broadcast
```crystal
def self.broadcast(message : String)
```
Envía un mensaje a todas las conexiones activas.

### send_to_one
```crystal
def self.send_to_one(identifier : String, message : String)
```
Envía un mensaje a un usuario específico.

### send_to_many
```crystal
def self.send_to_many(identifiers : Array(String), message : String)
```
Envía un mensaje a múltiples usuarios.

### send_to_group
```crystal
def self.send_to_group(group_name : String, message : String)
```
Envía un mensaje a todos los miembros de un grupo.

### add_to_group
```crystal
def self.add_to_group(identifier : String, group_name : String)
```
Añade un usuario a un grupo.

### get_group_members
```crystal
def self.get_group_members(group_name : String) : Set(String)
```
Obtiene los miembros de un grupo.

### get_connection_state
```crystal
def self.get_connection_state(socket : HTTP::WebSocket) : ConnectionState?
```
Obtiene el estado actual de una conexión.

### get_state_timestamp
```crystal
def self.get_state_timestamp(socket : HTTP::WebSocket) : Time?
```
Obtiene el timestamp del último cambio de estado.

### on_state_change
```crystal
def self.on_state_change(&block : HTTP::WebSocket, ConnectionState?, ConnectionState -> Nil)
```
Registra un callback para cambios de estado.

### set_connection_state
```crystal
def self.set_connection_state(socket : HTTP::WebSocket, state : ConnectionState)
```
Actualiza el estado de una conexión. Retorna void ya que el estado se procesa de forma asíncrona.

### set_retry_policy
```crystal
def self.set_retry_policy(socket : HTTP::WebSocket, policy : RetryPolicy)
```
Configura la política de reintentos para una conexión.

## Política de Reintentos

```crystal
class RetryPolicy
  property max_attempts : Int32         # Máximo número de intentos
  property base_delay : Time::Span      # Delay inicial
  property max_delay : Time::Span       # Delay máximo
  property backoff_multiplier : Float64 # Multiplicador de backoff
  property jitter : Float64            # Factor de aleatoriedad
end
```

## Ejemplos de Uso

```crystal
# Registrar una conexión
ConnectionManager.register(socket, "user_123")

# Configurar política de reintentos
policy = RetryPolicy.new(
  max_attempts: 5,
  base_delay: 1.seconds,
  max_delay: 30.seconds,
  backoff_multiplier: 2.0,
  jitter: 0.1
)
ConnectionManager.set_retry_policy(socket, policy)

# Gestión de grupos
ConnectionManager.add_to_group("user_123", "admins")
ConnectionManager.send_to_group("admins", "Mensaje solo para admins")

# Verificar estado
if state = ConnectionManager.get_connection_state(socket)
  case state
  when .connected?
    puts "Socket conectado"
  when .error?
    puts "Socket en error"
  end
end

# Envío de mensajes
ConnectionManager.send_to_one("user_123", "Mensaje privado")
ConnectionManager.broadcast("Mensaje para todos")

# Obtener información
puts "Conexiones activas: #{ConnectionManager.count}"
puts "Miembros del grupo: #{ConnectionManager.get_group_members("admins").join(", ")}"
```

## Manejo de Estados

```crystal
# Registrar hook para cambios de estado
ConnectionManager.on_state_change do |socket, old_state, new_state|
  puts "Socket cambió de #{old_state} a #{new_state}"
end

# Transiciones de estado
ConnectionManager.set_connection_state(socket, ConnectionState::Idle)
ConnectionManager.set_connection_state(socket, ConnectionState::Connected)
```

## Limpieza de Recursos

```crystal
# Limpiar todas las conexiones
ConnectionManager.clear

# Eliminar conexión específica
ConnectionManager.unregister(socket)
``` 