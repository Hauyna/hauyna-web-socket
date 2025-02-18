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
   - [Sistema de Limpieza Optimizado](#sistema-de-limpieza-optimizado)
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
    version: ~> 1.0.3
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
- 🧹 **Limpieza Optimizada**: Sistema lock-free con métricas atómicas y procesamiento por lotes

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
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Nueva conexión establecida"
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : JSON::Any) {
    puts "Mensaje recibido: #{message}"
    socket.send("Mensaje recibido!")
  },
  
  on_close: ->(socket : HTTP::WebSocket) {
    puts "Conexión cerrada"
  }
)

# Consultas optimizadas de presencia con manejo seguro de metadatos
def print_presence_info
  presence_data = Hauyna::WebSocket::Presence.list
  puts "Total usuarios online: #{presence_data.size}"
  
  users_in_channel = Hauyna::WebSocket::Presence.list_by_channel("general")
  puts "Usuarios en canal general: #{users_in_channel.size}"
  
  test_user = "user123"
  if Hauyna::WebSocket::Presence.present?(test_user)
    puts "#{test_user} está online"
  end
end

# Actualización thread-safe de metadata con validación robusta
def update_user_status(user_id : String, status : String)
  begin
    Hauyna::WebSocket::Presence.update(user_id, {
      "status" => JSON::Any.new(status),
      "last_activity" => JSON::Any.new(Time.local.to_unix_ms.to_s)
    })
    puts "Estado actualizado correctamente para #{user_id}"
  rescue ex : Exception
    puts "Error al actualizar estado: #{ex.message}"
  end
end

# Manejo de errores en presencia
def handle_presence_error(user_id : String)
  begin
    if presence = Hauyna::WebSocket::Presence.get_presence(user_id)
      puts "Estado: #{presence["state"]?.try(&.as_s) || "desconocido"}"
      
      if metadata = presence["metadata"]?
        begin
          error_data = JSON.parse(metadata.as_s)
          puts "Error: #{error_data["error_message"]?.try(&.as_s)}"
        rescue ex : JSON::ParseException
          puts "Error al parsear metadata: #{ex.message}"
        end
      end
    else
      puts "Usuario #{user_id} no encontrado"
    end
  rescue ex : Exception
    puts "Error al obtener presencia: #{ex.message}"
  end
end

# Monitoreo de cambios de presencia
Hauyna::WebSocket::Events.on("presence_change") do |socket, data|
  event_type = data["event"]?.try(&.as_s) || "unknown"
  user_id = data["user_id"]?.try(&.as_s) || "unknown"
  status = data["status"]?.try(&.as_s) || "unknown"
  
  case event_type
  when "join"
    puts "Usuario #{user_id} se unió con estado #{status}"
  when "leave"
    puts "Usuario #{user_id} se fue"
  when "update"
    puts "Usuario #{user_id} cambió su estado a #{status}"
  when "error"
    error_msg = data["error_message"]?.try(&.as_s) || "Error desconocido"
    puts "Error en presencia: #{error_msg}"
  else
    puts "Evento desconocido: #{event_type}"
  end
end

# Configurar el router y servidor
router = Hauyna::WebSocket::Router.new
router.websocket "/ws", handler

server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Servidor iniciado en http://localhost:8080"
server.listen(8080)

# Características del sistema de presencia mejorado:
# - Gestión centralizada con PresenceManager
# - Validación robusta de metadatos
#   - Campos requeridos (status)
#   - Validación de JSON
#   - Estados por defecto
#   - Preservación de datos
# - Campo status siempre presente con valor por defecto
# - Operaciones thread-safe optimizadas
# - Manejo consistente de estados
#   - Estados de error
#   - Transiciones válidas
#   - Preservación de estado
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

## Sistema de Limpieza Optimizado

### Configuración Dinámica

```crystal
# Configurar el sistema de limpieza con valores personalizados
config = Hauyna::WebSocket::CleanupConfig.new(
  batch_size: 50,     # Número máximo de canales a procesar por lote
  queue_size: 1000,   # Tamaño máximo de la cola de limpieza
  interval: 0.1,      # Intervalo entre procesamiento de lotes (segundos)
  max_retries: 3      # Máximo número de reintentos por operación
)

# Aplicar la configuración
Hauyna::WebSocket::Channel.configure_cleanup(config)

# Obtener la configuración actual
current_config = Hauyna::WebSocket::Channel.cleanup_config
puts "Tamaño de lote actual: #{current_config.batch_size}"
```

### Monitoreo y Métricas

```crystal

# Métodos de notificación y escalamiento
def notify_admin(message : String)
  # Por ejemplo: enviar email, mensaje a Slack, etc.
  puts "[ALERTA ADMIN] #{message}"
end

def scale_resources(reason : String)
  # Por ejemplo: aumentar workers, memoria, etc.
  puts "[ESCALAMIENTO] #{reason}"
end

# Definir umbrales de alerta
threshold = 100           # Umbral de errores permitidos
max_queue_size = 1000     # Tamaño máximo permitido de la cola

# Obtener métricas en tiempo real
metrics = Hauyna::WebSocket::Channel.cleanup_metrics
# Monitorear operaciones
puts "Estado del sistema de limpieza:"
puts "✓ Operaciones procesadas: #{metrics[:processed_count]}"
puts "✗ Errores encontrados: #{metrics[:error_count]}"
puts "□ Tamaño actual de cola: #{metrics[:queue_size]}"
puts "⌚ Tiempo promedio: #{metrics[:avg_process_time]}s"

# Configurar alertas basadas en métricas
if metrics[:error_count] > threshold
  notify_admin("Alto número de errores en limpieza")
end

if metrics[:queue_size] > max_queue_size
  scale_resources("Cola de limpieza saturada")
end

```

### Procesamiento por Lotes

```crystal
# Configurar procesamiento por lotes
handler = Hauyna::WebSocket::Handler.new(
  # Configuración de lotes
  cleanup_batch_size: 50,        # Tamaño máximo del lote
  cleanup_interval: 0.1,         # Intervalo entre procesamiento
  
  # Callbacks de procesamiento
  on_batch_start: ->(batch_size : Int32) {
    Log.info { "Iniciando procesamiento de lote: #{batch_size} operaciones" }
  },
  
  on_batch_complete: ->(processed : Int32, errors : Int32) {
    Log.info { "Lote completado - Procesadas: #{processed}, Errores: #{errors}" }
  }
)
```

### Testing y Desarrollo

```crystal
{% if flag?(:test) %}
# Simular operaciones concurrentes
Channel.testing_helper.simulate_concurrent_operations(100) do
  # Simular desconexiones
  socket = MockWebSocket.new
  Channel.cleanup_socket(socket)
end

# Verificar métricas después de pruebas
metrics = Channel.cleanup_metrics
assert metrics[:processed_count] == 100
assert metrics[:error_count] == 0

# Pruebas de carga
Channel.testing_helper.simulate_concurrent_operations(1000, parallel: 10) do
  # Operaciones de prueba
end
{% end %}
```

### Ejemplos de Uso Real

1. **Limpieza Automática en Desconexión**
```crystal
handler = Hauyna::WebSocket::Handler.new(
  on_close: ->(socket : HTTP::WebSocket) {
    # La limpieza se maneja automáticamente
    puts "Conexión cerrada, iniciando limpieza..."
  }
)
```

2. **Limpieza Manual**
```crystal
# Trigger manual de limpieza
socket = HTTP::WebSocket.new(url)
Channel.cleanup_socket(socket)

# Esperar confirmación de limpieza
sleep 0.2.seconds
metrics = Channel.cleanup_metrics
puts "Limpieza completada" if metrics[:processed_count] > 0
```

3. **Monitoreo Continuo**
```crystal
# Crear un monitor de métricas
spawn do
  loop do
    metrics = Channel.cleanup_metrics
    if metrics[:queue_size] > 100
      Log.warn { "Cola de limpieza creciendo: #{metrics[:queue_size]}" }
    end
    sleep 5.seconds
  end
end
```

### Mejores Prácticas

1. **Configuración Óptima**
```crystal
# Para sistemas pequeños
handler = Hauyna::WebSocket::Handler.new(
  cleanup_batch_size: 20,
  cleanup_interval: 0.2,
  max_cleanup_retries: 2
)

# Para sistemas grandes
handler = Hauyna::WebSocket::Handler.new(
  cleanup_batch_size: 100,
  cleanup_interval: 0.05,
  max_cleanup_retries: 5
)
```

2. **Monitoreo Efectivo**
```crystal
# Implementar sistema de alertas
def monitor_cleanup_system
  previous_metrics = Channel.cleanup_metrics
  
  spawn do
    loop do
      current_metrics = Channel.cleanup_metrics
      
      # Alertar si hay incremento significativo de errores
      if current_metrics[:error_count] - previous_metrics[:error_count] > 10
        alert_admin("Incremento significativo de errores en limpieza")
      end
      
      previous_metrics = current_metrics
      sleep 1.minute
    end
  end
end
```

3. **Manejo de Recursos**
```crystal
# Configurar límites seguros
handler = Hauyna::WebSocket::Handler.new(
  cleanup_queue_size: 1000,           # Límite de cola
  cleanup_memory_threshold: 100.MB,    # Límite de memoria
  cleanup_cpu_threshold: 0.8           # Límite de CPU
)
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
