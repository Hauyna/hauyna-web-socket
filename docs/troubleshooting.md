# Troubleshooting

## Problemas Comunes

### Conexión

#### No se puede establecer conexión
```
Error: Failed to connect to WebSocket server
```

**Posibles causas:**
1. Servidor no está corriendo
2. Puerto bloqueado
3. Configuración SSL incorrecta

**Soluciones:**
1. Verificar que el servidor esté activo
2. Revisar firewall y puertos
3. Validar certificados SSL

#### Desconexiones frecuentes
```
Error: Connection lost. Attempting to reconnect...
```

**Posibles causas:**
1. Problemas de red
2. Timeout del servidor
3. Sobrecarga de mensajes

**Soluciones:**
1. Verificar estabilidad de red
2. Ajustar timeouts
3. Implementar rate limiting

### Canales

#### Error al suscribirse
```
Error: Channel subscription failed
```

**Posibles causas:**
1. Canal no existe
2. Permisos insuficientes
3. Validación fallida

**Soluciones:**
1. Verificar nombre del canal
2. Revisar permisos
3. Validar parámetros

#### Mensajes no recibidos
```
Warning: Message delivery failed
```

**Posibles causas:**
1. Desuscripción accidental
2. Buffer lleno
3. Cliente desconectado

**Soluciones:**
1. Verificar suscripciones
2. Ajustar tamaño de buffer
3. Implementar cola de mensajes

## Debugging

### Logs

#### Habilitar logs detallados
```crystal
Hauyna::WebSocket.configure do |config|
  config.log_level = :debug
  config.verbose_logging = true
end
```

#### Filtrar logs por tipo
```crystal
Hauyna::WebSocket.configure do |config|
  config.log_filters = ["connection", "channel", "presence"]
end
```

### Monitoreo

#### Estado de conexiones
```crystal
ConnectionManager.status_report
```

#### Métricas de canales
```crystal
Channel.metrics
```

## Optimización

### Rendimiento

#### Ajustar buffers
```crystal
Hauyna::WebSocket.configure do |config|
  config.message_buffer_size = 1000
  config.max_concurrent_connections = 5000
end
```

#### Configurar timeouts
```crystal
handler = Hauyna::WebSocket::Handler.new(
  read_timeout: 30,
  write_timeout: 30,
  heartbeat_interval: 25.seconds
)
```

### Memoria

#### Limpiar recursos
```crystal
# Limpiar conexiones inactivas
ConnectionManager.cleanup_inactive

# Limpiar suscripciones huérfanas
Channel.cleanup_orphaned
```

#### Monitorear uso
```crystal
Hauyna::WebSocket.memory_stats
```

## Preguntas Frecuentes

### ¿Por qué mis mensajes llegan duplicados?

Posibles causas:
1. Múltiples suscripciones al mismo canal
2. Reconexión automática sin limpieza
3. Broadcast en cascada

Solución:
```crystal
# Verificar suscripciones actuales
Channel.subscribed_channels(socket)

# Implementar deduplicación
message_ids = Set(String).new
```

### ¿Cómo manejo reconexiones?

```crystal
handler = Hauyna::WebSocket::Handler.new do |config|
  config.on_reconnect = ->(socket : HTTP::WebSocket) {
    # Restaurar estado
    restore_session(socket)
    # Resuscribir a canales
    resubscribe_channels(socket)
  }
end
```

### ¿Cómo escalo horizontalmente?

1. Usar Redis para presencia
2. Implementar sticky sessions
3. Configurar balanceador de carga

```crystal
Hauyna::WebSocket.configure do |config|
  config.presence_adapter = Redis.new
  config.cluster_mode = true
end
``` 