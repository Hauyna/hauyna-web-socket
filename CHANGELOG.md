# Changelog

## [1.0.1] - 2024-03-19

### Changed
- Mejorado el manejo de timeouts usando el sistema de heartbeat en lugar de timeouts TCP
- Optimizado el manejo de conexiones para Crystal 1.15.0
- Mejorado el sistema de logging con nuevo módulo dedicado

### Added
- Nuevo módulo de logging con niveles configurables
- Manejo más específico de errores en ErrorHandler
  - Soporte para IO::Error
  - Soporte para Socket::Error
  - Mejor logging de errores no manejados
- Mutex para operaciones críticas en el sistema de canales

### Fixed
- Corregido el manejo de identificadores nulos en setup_connection
- Eliminados not_nil! innecesarios para mejor seguridad en tiempo de ejecución
- Mejorada la sincronización en operaciones de canales

## [1.0.0] - 2024-01-26

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

- Sistema de estados de conexión
  - Estados detallados (Connected, Disconnected, Reconnecting, Error, Idle)
  - Timestamps de cambios de estado
  - Notificaciones automáticas de cambios
  - Transiciones de estado validadas
  - Hooks para cambios de estado
  - Transiciones personalizables
  - Manejo seguro de transiciones inválidas
  - Integración con heartbeat y manejo de errores
  - Políticas de reintento configurables
  - Backoff exponencial con jitter
  - Límites de reintentos personalizables

### Security
- Validación de mensajes entrantes
- Timeouts configurables
- Limpieza automática de recursos
- Manejo básico de grupos y canales
- Validación de conexiones WebSocket
- Validación de estados de conexión
- Manejo seguro de transiciones de estado
- Limpieza automática de estados obsoletos
- Validación de transiciones de estado
- Manejo seguro de hooks de estado
- Protección contra transiciones inválidas

### Performance
- Operaciones thread-safe básicas
- Broadcast optimizado
- Manejo asíncrono de eventos
- Mutex para operaciones críticas
- Operaciones de estado thread-safe
- Manejo asíncrono de notificaciones de estado
- Optimización de consultas de estado
- Hooks asíncronos para cambios de estado
- Validación eficiente de transiciones

### Documentation
- README con ejemplos básicos
- Documentación inline de código
- Guía de contribución básica 