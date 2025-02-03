# Roadmap

## Próxima Versión [1.1.0]

### Prioridad Alta
- [ ] **Mejoras en Testing**
  - [ ] Aumentar cobertura de pruebas
  - [ ] Pruebas de integración básicas
  - [ ] Pruebas de concurrencia
  - [ ] Pruebas de timeouts y heartbeat
  - [ ] Pruebas de manejo de errores

### Características Implementadas ✅
- [x] **Mejoras en Testing**
  - [x] Estructura de tests organizada
  - [x] Tests de heartbeat mejorados
  - [x] Tests de conexión actualizados
- [x] **Sistema de Logging Avanzado**
  - [x] Módulo base de logging
  - [x] Niveles de log configurables
  - [x] Formateo básico de logs

- [x] **Estabilidad y Errores**
  - [x] Mejor manejo de errores de conexión
  - [x] Manejo mejorado de desconexiones y reconexiones
  - [x] Estados de conexión detallados
  - [x] Transiciones de estado personalizables
  - [x] Hooks para cambios de estado
  - [x] Políticas de reintentos personalizables

- [x] **Sistema de eventos básico**
  - [x] Registro de eventos
  - [x] Propagación de eventos
  - [x] Manejo de eventos por tipo

- [x] **Mejoras de Performance y Concurrencia**
  - [x] Sincronización con `Mutex`
  - [x] Operaciones thread-safe con canales (`ChannelOperation`)
  - [x] Manejo optimizado de conexiones
  - [x] Concurrencia robusta en **ConnectionManager**, **Channel** y **Presence**
  - [x] Limpieza automática con `CleanupOperation`

## Versión [1.2.0]

### Mejoras de Funcionalidad
- [ ] **Sistema de middleware para WebSocket**
  - [ ] Middleware de compresión
  - [ ] Middleware de rate limiting
  - [ ] Middleware de logging
  - [ ] Middleware de autenticación
  - [ ] Middleware de métricas

- [ ] **Estados de conexión avanzados**
  - [ ] Estados personalizables
  - [ ] Máquina de estados configurable
  - [ ] Políticas de transición
  - [ ] Estados por contexto

### Mejoras de Seguridad
- [ ] Rate limiting por conexión
- [ ] Validación de origen de conexiones
- [ ] Opciones de seguridad configurables
- [ ] Validación de transiciones de estado
- [ ] Auditoría de cambios de estado
- [ ] Protección contra ataques DoS

## Versión [2.0.0]

### Características Avanzadas
- [ ] Soporte para WebSocket sobre HTTP/2
- [ ] Protocolo de mensajería binaria
- [ ] Compresión per-message
- [ ] **Sistema de estados distribuido**
  - [ ] Sincronización de estados entre nodos
  - [ ] Persistencia de estados
  - [ ] Recuperación de estados
  - [ ] Replicación de estados

### Mejoras de Sistema
- [ ] **Canales mejorados**
  - [ ] Canales privados
  - [ ] Autorización por canal
  - [ ] Metadatos extendidos
  - [ ] Canales temporales

- [ ] **Sistema de presencia mejorado**
  - [ ] Estados personalizables
  - [ ] Timeouts configurables
  - [ ] Eventos detallados
  - [ ] Presencia por contexto

- [ ] **Integración avanzada de estados**
  - [ ] Estados por canal
  - [ ] Estados por grupo
  - [ ] Estados jerárquicos
  - [ ] Estados compartidos

## Mejoras Continuas

### Testing
- [ ] Aumentar cobertura de pruebas
- [ ] Pruebas de integración
- [ ] Pruebas de rendimiento
- [ ] Pruebas de concurrencia
- [ ] Pruebas de escenarios de fallo
- [ ] Pruebas de seguridad

### Documentación
- [ ] Documentación API completa
- [ ] Guías de uso avanzado
- [ ] Ejemplos de implementación
- [ ] Documentación multilenguaje
- [ ] Tutoriales interactivos

## Consideraciones Futuras

### Rendimiento
- [ ] Optimización de memoria
- [ ] Mejoras en concurrencia
- [ ] Optimización de broadcast
- [ ] Manejo eficiente de grandes grupos
- [ ] Caché inteligente
- [ ] Compresión adaptativa

---

> **Nota**: En la versión 1.0.1 se completaron diversas mejoras de concurrencia (uso de `Mutex`, canales de operaciones y limpieza automática), lo cual refuerza la estabilidad interna sin afectar la API externa. El enfoque ahora se centra en la ampliación de pruebas (testing) y la introducción de nuevas características en las próximas versiones.
