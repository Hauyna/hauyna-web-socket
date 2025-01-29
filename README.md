# Hauyna WebSocket

[![Crystal](https://img.shields.io/badge/Crystal-1.15.0-black?style=flat&logo=crystal&logoColor=white)](https://crystal-lang.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Hauyna WebSocket** es una biblioteca Crystal diseñada para simplificar la implementación de aplicaciones WebSocket en tiempo real. Proporciona un conjunto completo de herramientas para gestionar conexiones WebSocket, canales, grupos, seguimiento de presencia, manejo de eventos y más.

## Quick Start

```crystal
# 1. Añade la dependencia a shard.yml
dependencies:
  hauyna-web-socket:
    github: hauyna/hauyna-web-socket
    version: ~> 1.0.1

# 2. Crea un servidor básico
require "hauyna-web-socket"

handler = Hauyna::WebSocket::Handler.new(
  extract_identifier: ->(socket, params) { params["user_id"]?.try(&.as_s) || "anon" }
)

router = Hauyna::WebSocket::Router.new
router.websocket "/ws", handler

server = HTTP::Server.new do |context|
  router.call(context)
end

server.listen(8080)
```

## 🚀 Características Principales

- 📡 **Sistema de canales para comunicación en tiempo real**
  - Suscripciones flexibles a múltiples canales
  - Broadcast selectivo por canal
  - Gestión de metadatos por suscripción
  - Eventos automáticos de suscripción/desuscripción
  - Limpieza automática de suscripciones

- 👥 **Sistema de presencia con metadatos**
  - Tracking en tiempo real de usuarios
  - Metadatos personalizables por usuario
  - Filtrado por canal o grupo
  - Eventos de cambio de estado
  - Consultas por criterios múltiples

- 🔄 **Gestión de conexiones y grupos**
  - Identificación única de conexiones
  - Sistema de grupos dinámicos
  - Mensajería directa y broadcast
  - Limpieza automática de conexiones
  - Gestión thread-safe con mutex

- ❤️ **Características Avanzadas**
  - Heartbeat automático
  - Reconexión automática
  - Manejo de errores robusto
  - Estados de conexión detallados
  - Sistema de logging configurable

## Arquitectura

### Diagrama General

```mermaid
graph TB
    Client[Cliente WebSocket] -->|WebSocket| Server[Servidor Hauyna]
    Server -->|Eventos| Handler[Handler]
    Handler -->|Operaciones| ChannelManager[Channel Manager]
    Handler -->|Validación| MessageValidator[Message Validator]
    Handler -->|Operaciones| PresenceSystem[Presence System]
    Handler -->|Operaciones| ConnectionManager[Connection Manager]
```

### Flujo de Operaciones

```mermaid
sequenceDiagram
    participant C as Cliente
    participant H as Handler
    participant Ch as Channel
    participant P as Presence
    participant CM as ConnectionManager
    
    C->>H: Conexión WebSocket
    H->>CM: Registrar Conexión
    H->>Ch: Suscribir a Canales
    H->>P: Actualizar Presencia
    
    Note over C,H: Si hay desconexión
    C--xH: Conexión Perdida
    H->>CM: Marcar Desconectado
    H->>P: Actualizar Estado
    
    Note over C,H: Reconexión
    C->>H: Nueva Conexión
    H->>CM: Reconectar
    H->>Ch: Restaurar Suscripciones
    H->>P: Actualizar Presencia
```

### Sistema de Canales

```mermaid
graph LR
    subgraph "Canal de Operaciones"
        Op1[Subscribe] --> Processor
        Op2[Unsubscribe] --> Processor
        Op3[Broadcast] --> Processor
        Op4[Presence] --> Processor
        Processor[Procesador de Operaciones]
    end
    
    subgraph "Estado del Sistema"
        Processor -->|Actualiza| State[Estado de Canales]
        State -->|Lee| Queries[Consultas]
        State -->|Notifica| Presence[Sistema de Presencia]
    end
    
    subgraph "Comunicación"
        Processor -->|Envía| Messages[Mensajes]
        Messages -->|Broadcast| Clients[Clientes]
        Messages -->|Eventos| Events[Eventos del Sistema]
    end
```

### Sistema de Retry y Heartbeat

```mermaid
graph TB
    subgraph "Sistema de Heartbeat"
        HB[Heartbeat Manager] -->|Ping| Socket[WebSocket]
        Socket -->|Pong| HB
        HB -->|Timeout| Retry[Retry System]
    end

    subgraph "Sistema de Retry"
        Retry -->|Calcula Delay| Policy[Retry Policy]
        Policy -->|Exponential Backoff| Attempt[Retry Attempt]
        Attempt -->|Success| Connected[Conexión Restaurada]
        Attempt -->|Failure| NextRetry[Siguiente Intento]
        NextRetry -->|Max Attempts| Failed[Fallo Permanente]
    end

    subgraph "Estados de Conexión"
        Connected -->|Error| Disconnected[Desconectado]
        Disconnected -->|Retry| Attempting[Intentando Reconexión]
        Attempting -->|Success| Connected
        Attempting -->|Failure| Failed
    end
```

### Sistema de Validación de Mensajes

```mermaid
graph LR
    subgraph "Flujo de Validación"
        Raw[Mensaje Raw] -->|Parse| JSON[JSON Parser]
        JSON -->|Validar Estructura| Validator[Message Validator]
        Validator -->|Validar Tipo| TypeCheck[Type Checker]
        TypeCheck -->|Validar Contenido| ContentCheck[Content Validator]
    end

    subgraph "Manejo de Errores"
        JSON -->|Error| ParseError[Parse Error]
        Validator -->|Error| ValidationError[Validation Error]
        TypeCheck -->|Error| TypeError[Type Error]
        ContentCheck -->|Error| ContentError[Content Error]
    end

    subgraph "Resultado"
        ContentCheck -->|Success| Valid[Mensaje Válido]
        ParseError -->|Handle| ErrorHandler[Error Handler]
        ValidationError -->|Handle| ErrorHandler
        TypeError -->|Handle| ErrorHandler
        ContentError -->|Handle| ErrorHandler
    end
```

### Sistema de Grupos y Canales

```mermaid
graph TB
    subgraph "Gestión de Grupos"
        Group[Grupo] -->|Contiene| Members[Miembros]
        Members -->|Pertenece| User[Usuario]
        Group -->|Asociado| Channels[Canales]
    end

    subgraph "Gestión de Canales"
        Channel[Canal] -->|Suscribe| Subscribers[Suscriptores]
        Channel -->|Broadcast| Messages[Mensajes]
        Channel -->|Gestiona| Presence[Presencia]
    end

    subgraph "Interacción"
        User -->|Suscribe| Channel
        User -->|Envía| Messages
        User -->|Actualiza| Presence
        Group -->|Broadcast| Messages
    end

    subgraph "Permisos"
        Group -->|Define| Permissions[Permisos]
        Permissions -->|Controla| Access[Acceso]
        Access -->|Restringe| Channel
        Access -->|Autoriza| User
    end
```

### Sistema de Eventos y Notificaciones

```mermaid
sequenceDiagram
    participant Client as Cliente
    participant Handler as Event Handler
    participant Channel as Canal
    participant Notification as Sistema de Notificaciones
    participant Presence as Sistema de Presencia

    Client->>Handler: Evento de Usuario
    Handler->>Channel: Procesar Evento
    
    alt Evento de Canal
        Channel->>Notification: Generar Notificación
        Notification-->>Client: Enviar Notificación
    else Evento de Presencia
        Channel->>Presence: Actualizar Estado
        Presence-->>Client: Broadcast Estado
    end

    Handler->>Client: Confirmar Procesamiento
```

## Compatibilidad

| Crystal Version | Hauyna Version | Estado |
|----------------|----------------|---------|
| 1.15.x         | 1.0.1         | ✅      |
| 1.14.x         | 1.0.0         | ✅      |

## Documentación

- [Guía de Chat](docs/guides/chat.md)
- [Sistema de Notificaciones](docs/guides/notifications.md)
- [Sistema de Presencia](docs/guides/presence.md)
- [API Reference](docs/API.md)
- [Ejemplos Avanzados](docs/examples.md)
- [Troubleshooting](docs/troubleshooting.md)

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
