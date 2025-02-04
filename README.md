# Hauyna WebSocket

[![Crystal](https://img.shields.io/badge/Crystal-1.15.0-black?style=flat&logo=crystal&logoColor=white)](https://crystal-lang.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Biblioteca Crystal ligera y rápida para WebSockets en tiempo real. Simple pero poderosa.

## Índice

1. [Instalación](#instalación)
2. [Uso Básico](#uso-básico)
3. [Características](#características)
4. [Características Principales](#características-principales)
   - [Estados de Conexión](#estados-de-conexión)
   - [Política de Reintentos](#política-de-reintentos)
   - [Manejo de Errores](#manejo-de-errores)
   - [Canales y Broadcast](#canales-y-broadcast)
   - [Sistema de Heartbeat](#sistema-de-heartbeat)
   - [Sistema de Presencia](#sistema-de-presencia)
   - [Grupos y Mensajes Directos](#grupos-y-mensajes-directos)
   - [Manejo de Eventos](#manejo-de-eventos)
5. [Ejemplos](#ejemplos)
6. [Contribuir](#contribuir)
7. [Autores](#autores)
8. [Licencia](#licencia)

## Instalación

Añade esto a tu `shard.yml`:

```yaml
dependencies:
  hauyna-web-socket:
    github: hauyna/hauyna-web-socket
    version: ~> 1.0.2
```

## Uso Básico

```crystal
require "hauyna-web-socket"

# Configurar el handler con callbacks básicos y política de reintentos
handler = Hauyna::WebSocket::Handler.new(
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Nueva conexión establecida"
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    puts "Mensaje recibido: #{message}"
    socket.send("Mensaje recibido!")
  },
  
  on_close: ->(socket : HTTP::WebSocket) {
    puts "Conexión cerrada"
  },
  
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    params["user_id"]?.try(&.as_s) || "anon"
  },
  
  heartbeat_interval: 30.seconds,
  heartbeat_timeout: 60.seconds
)

# Configurar política de reintentos personalizada
retry_policy = Hauyna::WebSocket::ConnectionManager::RetryPolicy.new(
  max_attempts: 5,
  base_delay: 1.seconds,
  max_delay: 30.seconds,
  backoff_multiplier: 2.0,
  jitter: 0.1
)

# Configurar el router
router = Hauyna::WebSocket::Router.new
router.websocket "/ws", handler

# Iniciar el servidor
server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Servidor WebSocket iniciado en ws://localhost:8080/ws"
server.listen(8080)
```

## Características

- 🚀 **Alto Rendimiento**: Diseñado para manejar miles de conexiones concurrentes
- 📡 **Sistema de Canales**: Suscripciones y broadcast en tiempo real
- 👥 **Sistema de Presencia**: Tracking de usuarios con metadatos y gestión centralizada
- 🔄 **Gestión de Conexiones**: Grupos, mensajes directos y broadcast
- ❤️ **Características Pro**: Heartbeat, reconexión automática, manejo de errores
- 🔒 **Thread-Safe**: Operaciones seguras con mutex y gestión centralizada
- 🎯 **Gestión Centralizada**: Sistema de presencia optimizado con patrón Singleton
- 📊 **Monitoreo Mejorado**: Buffer configurable y mejor control de recursos

## Características Principales

### Estados de Conexión

El sistema implementa los siguientes estados de conexión y sus transiciones permitidas:

```crystal
enum ConnectionState
  Connected    # Conexión establecida y activa
  Disconnected # Conexión terminada
  Reconnecting # Intentando reconexión
  Error        # Error en la conexión
  Idle         # Conexión inactiva
end

# Transiciones válidas entre estados:
# Connected    -> Idle, Disconnected, Error
# Idle         -> Connected, Disconnected, Error  
# Disconnected -> Reconnecting, Error
# Reconnecting -> Connected, Error
# Error        -> Reconnecting

# Monitorear cambios de estado
Hauyna::WebSocket::ConnectionManager.on_state_change do |socket, old_state, new_state|
  puts "Conexión cambió de #{old_state} a #{new_state}"
end
```

### Política de Reintentos

La biblioteca incluye una política de reintentos configurable:

```crystal
# Configurar política de reintentos personalizada
retry_policy = Hauyna::WebSocket::ConnectionManager::RetryPolicy.new(
  max_attempts: 5,        # Número máximo de intentos de reconexión
  base_delay: 1.seconds,  # Retraso inicial entre intentos
  max_delay: 30.seconds,  # Retraso máximo entre intentos
  backoff_multiplier: 2.0,# Multiplicador para incremento exponencial
  jitter: 0.1            # Factor de aleatoriedad (0.0 - 1.0) para evitar tormentas de reconexión
)

# El jitter añade una variación aleatoria al retraso calculado:
# delay_final = delay_base ± (delay_base * jitter)
# Ejemplo: Con delay_base=1s y jitter=0.1, el retraso final será entre 0.9s y 1.1s

# Asignar política a una conexión
socket = HTTP::WebSocket.new(url)
Hauyna::WebSocket::ConnectionManager.set_retry_policy(socket, retry_policy)
```

### Manejo de Errores

```crystal
# Errores personalizados en callbacks
handler = Hauyna::WebSocket::Handler.new(
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    begin
      # Tu lógica aquí
    rescue ex : JSON::ParseException
      # El ErrorHandler se encargará automáticamente
      raise ex
    rescue ex : IO::Error
      # Se cerrará automáticamente el socket con código 1006
      raise ex
    end
  }
)

# El sistema maneja automáticamente:
# - Errores de conexión (IO::Error) con cierre de socket
# - Errores de socket (Socket::Error)
# - Errores de validación y parsing
# - Errores de runtime y tipo
# - Logging detallado de errores
# - Limpieza segura de recursos
```

### Canales y Broadcast

```crystal
require "hauyna-web-socket"

# Configurar el handler con soporte para canales
handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) { params["user_id"]?.try(&.as_s) || "anon" },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    user_id = params["user_id"]?.try(&.as_s) || "anon"
    
    # Suscribir al usuario cuando se conecta
    Hauyna::WebSocket::Channel.subscribe("chat", socket, user_id, {
      "username" => JSON::Any.new("john_doe"),
      "room" => JSON::Any.new("general")
    })
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    # Manejo de diferentes tipos de broadcast
    case message["type"]?.try(&.as_s)
    when "broadcast_all"
      # Broadcast a todos los usuarios conectados
      Hauyna::WebSocket::Events.broadcast(message["content"].to_json)
    
    when "broadcast_channel"
      # Broadcast a un canal específico
      if channel = message["channel"]?.try(&.as_s)
        content = case message["content"]
        when .as_h?
          message["content"].as_h
        else
          {"message" => message["content"]} of String => JSON::Any
        end
        Hauyna::WebSocket::Channel.broadcast_to(channel, content)
      end
    
    when "broadcast_group"
      # Broadcast a un grupo
      if group = message["group"]?.try(&.as_s)
        Hauyna::WebSocket::ConnectionManager.send_to_group(group, message["content"].to_json)
      end
    
    when "direct_message"
      # Mensaje directo a un usuario
      if recipient = message["recipient"]?.try(&.as_s)
        Hauyna::WebSocket::ConnectionManager.send_to_one(recipient, message["content"].to_json)
      end
    end
  },
  
  on_close: ->(socket : HTTP::WebSocket) {
    # Limpiar suscripciones cuando el usuario se desconecta
    channels = Hauyna::WebSocket::Channel.subscribed_channels(socket)
    channels.each do |channel|
      Hauyna::WebSocket::Channel.unsubscribe(channel, socket)
    end
  }
)

# Configurar el router
router = Hauyna::WebSocket::Router.new
router.websocket "/ws", handler

server = HTTP::Server.new do |context|
  router.call(context)
end

server.listen(8080)
```

Ejemplos de mensajes para diferentes tipos de broadcast:

```crystal
# Broadcast a todos los usuarios
{
  "type": "broadcast_all",
  "content": {
    "message": "Anuncio para todos"
  }
}

# Broadcast a un canal
{
  "type": "broadcast_channel",
  "channel": "chat",
  "content": {
    "message": "Mensaje para el canal chat"
  }
}

# Broadcast a un grupo
{
  "type": "broadcast_group",
  "group": "admins",
  "content": {
    "message": "Mensaje para administradores"
  }
}

# Mensaje directo
{
  "type": "direct_message",
  "recipient": "user123",
  "content": {
    "message": "Mensaje privado"
  }
}
```

### Sistema de Heartbeat

El sistema de heartbeat ayuda a mantener las conexiones activas y detectar desconexiones:

```crystal
# Configurar el handler con heartbeat personalizado
handler = Hauyna::WebSocket::Handler.new(
  heartbeat_interval: 30.seconds,  # Intervalo entre pings
  heartbeat_timeout: 60.seconds    # Tiempo máximo de espera para pong
)

# El sistema de heartbeat:
# 1. Envía un ping cada heartbeat_interval
# 2. Espera un pong dentro de heartbeat_timeout
# 3. Si no recibe pong, marca la conexión como Error

# Personalizar callbacks de heartbeat
handler = Hauyna::WebSocket::Handler.new(
  on_ping: ->(socket : HTTP::WebSocket, message : String) {
    # Ejecutado cuando se recibe un ping
    puts "Ping recibido: #{message}"
  },
  
  on_pong: ->(socket : HTTP::WebSocket, message : String) {
    # Ejecutado cuando se recibe un pong
    puts "Pong recibido: #{message}"
  },
  
  heartbeat_interval: 30.seconds,
  heartbeat_timeout: 60.seconds
)

# El sistema maneja automáticamente:
# - Detección de conexiones muertas
# - Limpieza de recursos
# - Reconexión automática si está configurada
# - Métricas de latencia
```


### Sistema de Presencia

El sistema de presencia permite rastrear usuarios conectados y su estado en tiempo real, con gestión centralizada y manejo robusto de metadatos:

```crystal
require "hauyna-web-socket"

# Configurar el handler con sistema de presencia mejorado
handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    user_id = params["user_id"]?.try(&.as_s)
    return "anonymous" unless user_id
    
    # Tracking con metadata (el campo status es requerido y tendrá valor por defecto si no se especifica)
    metadata = {
      "user_id" => JSON::Any.new(user_id),
      "status" => JSON::Any.new("online"),  # Campo requerido, por defecto "online"
      "channel" => JSON::Any.new("general"),
      "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
    } of String => JSON::Any
    
    # Tracking a través del PresenceManager con validación de metadatos
    Hauyna::WebSocket::Presence.track(user_id, metadata)
    
    user_id
  }
)

# Consultas optimizadas de presencia con manejo seguro de metadatos
presence_data = Hauyna::WebSocket::Presence.list  # Incluye status por defecto si falta
users_in_channel = Hauyna::WebSocket::Presence.list_by_channel("general")
is_online = Hauyna::WebSocket::Presence.present?("user123")
user_count = Hauyna::WebSocket::Presence.count

# Actualización thread-safe de metadata con validación
Hauyna::WebSocket::Presence.update("user123", {
  "status" => JSON::Any.new("away"),     # Campo requerido
  "last_activity" => JSON::Any.new(Time.local.to_unix_ms.to_s)
})

# Monitoreo de cambios de presencia con estados consistentes
Hauyna::WebSocket::Events.on("presence_change") do |socket, data|
  case data["event"]?.try(&.as_s)
  when "join"
    puts "Usuario #{data["user_id"]} se unió con estado #{data["status"]}"
  when "leave"
    puts "Usuario #{data["user_id"]} se fue"
  when "update"
    puts "Usuario #{data["user_id"]} cambió su estado a #{data["status"]}"
  end
end

# Características del sistema de presencia mejorado:
# - Gestión centralizada con PresenceManager
# - Validación robusta de metadatos
# - Campo status siempre presente con valor por defecto
# - Operaciones thread-safe optimizadas
# - Manejo consistente de estados
# - API clara y predecible
# - Mejor manejo de errores y logging
```


### Grupos y Mensajes Directos

```crystal
require "hauyna-web-socket"

# Configurar el handler con soporte para grupos
handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    params["user_id"]?.try(&.as_s) || "anonymous"  # Devolvemos "anonymous" si no hay user_id
  }
)

# Gestión de grupos
user_id = "user123"
Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "admins")

# Verificar pertenencia a grupo
is_admin = Hauyna::WebSocket::ConnectionManager.is_in_group?(user_id, "admins")

# Enviar mensaje a grupo
if is_admin
  Hauyna::WebSocket::ConnectionManager.send_to_group("admins", {
    "type" => JSON::Any.new("notification"),
    "message" => JSON::Any.new("Mensaje para admins")
  }.to_json)
end

# Mensaje directo
recipient_id = "user456"
Hauyna::WebSocket::ConnectionManager.send_to_one(recipient_id, {
  "type" => JSON::Any.new("direct_message"),
  "from" => JSON::Any.new(user_id),
  "message" => JSON::Any.new("Hola!")
}.to_json)
```
### Manejo de Eventos

```crystal
require "hauyna-web-socket"

# Registrar manejadores de eventos
Hauyna::WebSocket::Events.on("user_joined") do |socket, data|
  username = data["username"].as_s
  Hauyna::WebSocket::Channel.broadcast_to("chat", {
    "type" => JSON::Any.new("system"),
    "text" => JSON::Any.new("#{username} se ha unido")
  })
end

Hauyna::WebSocket::Events.on("message_received") do |socket, data|
  # Validar y procesar mensaje
  if data["content"]?
    Hauyna::WebSocket::Channel.broadcast_to(data["channel"].as_s, {
      "type" => JSON::Any.new("message"),
      "from" => JSON::Any.new(data["user"].as_s),
      "content" => JSON::Any.new(data["content"].as_s)
    })
  end
end
```

## Ejemplos

> **Nota**: Los ejemplos están en desarrollo y serán añadidos próximamente.
- Chat Simple (próximamente)
- Sistema de Notificaciones (próximamente) 
- Juego Multijugador (próximamente)


## Contribuir

1. Fork it (<https://github.com/hauyna/hauyna-web-socket/fork>)
2. Crea tu rama (`git checkout -b my-new-feature`)
3. Commit tus cambios (`git commit -am 'Add some feature'`)
4. Push a la rama (`git push origin my-new-feature`)
5. Crea un Pull Request

## Autores

<table>
  <tr>
    <td align="center">
      <a href="https://github.com/Stockers-JAPG">
        <img src="https://github.com/Stockers-JAPG.png" width="100px;" alt="José Antonio Padre García"/><br />
        <sub><b>José Antonio Padre García</b></sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/LuisPadre25">
        <img src="https://github.com/LuisPadre25.png" width="100px;" alt="Luis Antonio Padre García"/><br />
        <sub><b>Luis Antonio Padre García</b></sub>
      </a>
    </td>
  </tr>
</table>

## Licencia

Este proyecto está licenciado bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para más detalles.
