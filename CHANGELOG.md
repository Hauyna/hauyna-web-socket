# Changelog

## [1.0.0] - 2024-XX-XX

### Added
- Sistema de canales para comunicación en tiempo real
  - Suscripciones flexibles a múltiples canales
  - Broadcast selectivo por canal
  - Gestión de metadatos por suscripción
  - Eventos automáticos de suscripción/desuscripción
  - Limpieza automática de suscripciones
  - Verificación de suscripciones
  - Obtención de metadatos de suscripción

- Sistema de presencia con metadatos
  - Tracking en tiempo real de usuarios
  - Metadatos personalizables por usuario
  - Filtrado por canal o grupo
  - Eventos de cambio de estado (join/leave/update)
  - Consultas por criterios múltiples
  - Conteo y estadísticas de presencia
  - Verificación de presencia
  - Actualización de estado en tiempo real

- Gestión de conexiones y grupos
  - Identificación única de conexiones
  - Sistema de grupos dinámicos
  - Mensajería directa y broadcast
  - Limpieza automática de conexiones
  - Gestión thread-safe con mutex
  - Obtención de conexiones por identificador
  - Manejo de grupos de usuarios
  - Envío de mensajes a grupos

- Sistema de eventos básico
  - Registro de manejadores de eventos
  - Callbacks configurables
  - Manejo básico de errores
  - Broadcast de eventos

- Heartbeat básico
  - Intervalos configurables
  - Timeouts personalizables
  - Monitoreo de estado
  - Limpieza de conexiones inactivas
  - Registro de pongs

- Manejo de errores
  - Validación de mensajes
  - Errores tipados básicos
  - Respuestas de error formateadas
  - Logging básico
  - Manejo de errores de conexión

- Router WebSocket
  - Rutas con parámetros
  - Extracción de parámetros
  - Validación de conexiones
  - Contexto HTTP básico
  - Manejo de upgrade WebSocket

### Security
- Validación de mensajes entrantes
- Timeouts configurables
- Limpieza automática de recursos
- Manejo básico de grupos y canales
- Validación de conexiones WebSocket

### Performance
- Operaciones thread-safe básicas
- Broadcast optimizado
- Manejo asíncrono de eventos
- Mutex para operaciones críticas

### Documentation
- README con ejemplos básicos
- Documentación inline de código
- Guía de contribución básica 