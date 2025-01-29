# API Reference

Esta documentación describe la API completa de Hauyna WebSocket.

## Módulos Principales

### [Channel](api/channel.md)
Sistema de canales para comunicación en tiempo real.
- Suscripción y desuscripción de canales
- Broadcast a canales específicos
- Manejo de metadatos por suscripción
- Sistema de operaciones asíncronas
- Reconexión automática de suscripciones

### [Connection Manager](api/connection_manager.md)
Gestión de conexiones WebSocket.
- Registro y seguimiento de conexiones
- Estados de conexión (Connected, Disconnected, Reconnecting, Error, Idle)
- Sistema de grupos
- Política de reintentos configurable
- Operaciones thread-safe con mutex

### [Events](api/events.md)
Sistema de eventos personalizable.
- Registro de manejadores de eventos
- Broadcasting global
- Manejo de eventos por tipo
- Callbacks tipados con EventCallback

### [Handler](api/handler.md)
Manejador principal de WebSocket.
- Callbacks configurables (on_open, on_message, on_close, on_ping, on_pong)
- Extracción de identificadores
- Sistema de heartbeat
- Procesamiento de mensajes
- Manejo de canales

### [Presence](api/presence.md)
Sistema de presencia en tiempo real.
- Tracking de usuarios
- Metadatos por usuario
- Operaciones asíncronas
- Consultas de presencia
- Estado por canal y grupo

### [Router](api/router.md)
Enrutamiento de WebSocket.
- Registro de rutas WebSocket
- Manejo de parámetros de ruta
- Integración con HTTP::Server
- Procesamiento de contexto

## Módulos de Soporte

### Error Handler
- Manejo de errores de validación
- Errores de conexión
- Errores de socket
- Logging de errores

### Message Validator
- Validación de formato de mensajes
- Validación de tipos de mensaje
- Validación de parámetros requeridos

### Logging
- Sistema de logging configurable
- Niveles de log personalizables
- Backend de logging configurable

## Guías Relacionadas

- [Implementación de Chat](guides/chat.md)
- [Sistema de Notificaciones](guides/notifications.md)
- [Sistema de Presencia](guides/presence.md)

## Ejemplos Prácticos

Encuentra ejemplos completos de implementación en el directorio [examples/](examples/).

## Troubleshooting

Para problemas comunes y sus soluciones, consulta la [guía de troubleshooting](troubleshooting.md) 