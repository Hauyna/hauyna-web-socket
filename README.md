# Hauyna WebSocket

Hauyna WebSocket es una biblioteca Crystal diseñada para simplificar la implementación de aplicaciones WebSocket en tiempo real. Proporciona una API intuitiva y robusta para manejar conexiones WebSocket, gestionar grupos de usuarios y enviar mensajes de manera eficiente.

## Índice

- [Características Principales](#características-principales)
  - [Gestión de Conexiones](#gestión-de-conexiones)
  - [Sistema de Grupos](#sistema-de-grupos)
  - [Patrones de Mensajería](#patrones-de-mensajería)
  - [Manejo de Eventos](#manejo-de-eventos)
  - [Características de Seguridad](#características-de-seguridad)
- [Casos de Uso](#casos-de-uso)
- [Instalación](#instalación)
- [Uso Básico](#uso-básico)
- [API](#api)
- [Ventajas](#ventajas)
- [Requisitos](#requisitos)
- [Contribución](#contribución)
- [Contribuidores](#contribuidores)
- [Licencia](#licencia)
- [Características Destacadas](#características-destacadas)


## Características Principales

### Gestión de Conexiones
- Registro y seguimiento automático de conexiones WebSocket
- Identificación única de clientes
- Manejo seguro de desconexiones
- Soporte para múltiples conexiones simultáneas

### Sistema de Grupos
- Creación dinámica de grupos de usuarios
- Capacidad para añadir/remover usuarios de grupos
- Envío de mensajes a grupos específicos
- Gestión eficiente de membresías múltiples

### Patrones de Mensajería
- Broadcast a todos los clientes conectados
- Envío dirigido a usuarios específicos
- Mensajería grupal
- Soporte para diferentes formatos de mensaje

### Manejo de Eventos
- Sistema de eventos personalizable
- Callbacks para conexión, desconexión y mensajes
- Manejo de errores robusto
- Eventos personalizados definidos por el usuario

### Características de Seguridad
- Sincronización thread-safe con mutex
- Manejo seguro de desconexiones inesperadas
- Limpieza automática de conexiones muertas
- Validación de mensajes y conexiones

### Sistema de Heartbeat y Auto-Reconexión

Hauyna WebSocket incluye un sistema robusto de heartbeat y auto-reconexión para mantener las conexiones estables:

#### Heartbeat del Servidor

```crystal
# Configurar handler con heartbeat
handler = Hauyna::WebSocket::Handler.new(
  heartbeat_interval: 30.seconds,  # Intervalo entre pings
  heartbeat_timeout: 60.seconds,   # Tiempo máximo sin respuesta
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Nueva conexión establecida"
  }
)

# El heartbeat se maneja automáticamente:
# - Envía pings periódicos
# - Monitorea pongs
# - Cierra conexiones inactivas
# - Limpia recursos automáticamente
```

#### Cliente con Auto-Reconexión

```javascript
class WebSocketClient {
  constructor(url, options = {}) {
    this.url = url;
    this.options = {
      reconnectInterval: 1000,      // Intervalo entre intentos
      maxReconnectAttempts: 5,      // Máximo de intentos
      heartbeatInterval: 30000,     // Intervalo de heartbeat
      ...options
    };
    
    this.connect();
  }

  connect() {
    this.ws = new WebSocket(this.url);
    this.setupHeartbeat();
    this.setupReconnection();
  }

  setupHeartbeat() {
    // Enviar heartbeat periódicamente
    this.heartbeatInterval = setInterval(() => {
      if (this.ws.readyState === WebSocket.OPEN) {
        this.ws.send(JSON.stringify({ type: 'heartbeat' }));
      }
    }, this.options.heartbeatInterval);
  }

  setupReconnection() {
    this.ws.onclose = () => {
      if (this.reconnectAttempts < this.options.maxReconnectAttempts) {
        setTimeout(() => this.connect(), this.options.reconnectInterval);
        this.reconnectAttempts++;
      }
    };
  }
}

// Uso del cliente
const ws = new WebSocketClient('ws://localhost:3000/chat', {
  reconnectInterval: 2000,
  maxReconnectAttempts: 3,
  heartbeatInterval: 25000
});
```

#### Características del Sistema

- **Heartbeat del Servidor**:
  - 🔄 Monitoreo automático de conexiones activas
  - ⏱️ Intervalos configurables de ping/pong
  - 🚫 Cierre automático de conexiones muertas
  - 🧹 Limpieza automática de recursos

- **Auto-Reconexión del Cliente**:
  - 🔁 Reconexión automática en desconexiones
  - ⚙️ Intentos de reconexión configurables
  - ⏰ Intervalos de espera personalizables
  - 📊 Eventos para monitorear el estado

- **Beneficios**:
  - 💪 Conexiones más estables y robustas
  - 🛡️ Recuperación automática de fallos
  - 📉 Reducción de conexiones fantasma
  - 🔍 Mejor monitoreo del estado de conexión

## Casos de Uso

La biblioteca es ideal para implementar:

- Chats en tiempo real
- Sistemas de notificaciones push
- Monitoreo en vivo
- Juegos multijugador
- Aplicaciones colaborativas
- Dashboards en tiempo real
- Sistemas IoT
- Streaming de datos

## Instalación

1. Agrega la dependencia a tu `shard.yml`:

```yaml
dependencies:
  hauyna-web-socket:
    github: tu-usuario/hauyna-web-socket
```

2. Instala las dependencias:

```bash
shards install
```

3. Importa la librería:

```crystal
require "hauyna-web-socket"
```

## Uso Básico

```crystal
require "hauyna-web-socket"

# Crear un manejador WebSocket
handler = Hauyna::WebSocket::Handler.new(
  # Identificar usuarios únicos
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    params["user_id"]?.try(&.as_s)
  },

  # Manejar conexión nueva
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    user_id = params["user_id"]?.try(&.as_s)
    room = params["room"]?.try(&.as_s) || "general"
    
    # Agregar usuario a un grupo
    Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, room) if user_id
    
    # Notificar a todos en el grupo
    Hauyna::WebSocket::Events.send_to_group(room, {
      type: "user_joined",
      user: user_id
    }.to_json)
  },

  # Manejar mensajes
  on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
    case data["type"]?.try(&.as_s)
    when "broadcast"
      Hauyna::WebSocket::Events.broadcast(data["message"].to_json)
    when "private"
      if recipient = data["to"]?.try(&.as_s)
        Hauyna::WebSocket::Events.send_to_one(recipient, data["message"].to_json)
      end
    when "group"
      if group = data["room"]?.try(&.as_s)
        Hauyna::WebSocket::Events.send_to_group(group, data["message"].to_json)
      end
    end
  }
)

# Configurar rutas
router = Hauyna::WebSocket::Router.new
router.websocket("/chat", handler)

# Iniciar servidor
server = HTTP::Server.new do |context|
  router.call(context)
end

server.listen("0.0.0.0", 3000)
```

### Cliente JavaScript

```javascript
// Conectar con parámetros
const ws = new WebSocket('ws://localhost:3000/chat?user_id=123&room=general');

// Enviar mensaje broadcast
ws.send(JSON.stringify({
  type: 'broadcast',
  message: 'Hola a todos!'
}));

// Enviar mensaje privado
ws.send(JSON.stringify({
  type: 'private',
  to: 'user456',
  message: 'Hola usuario específico!'
}));

// Enviar mensaje a grupo
ws.send(JSON.stringify({
  type: 'group',
  room: 'general',
  message: 'Hola grupo!'
}));

// Recibir mensajes
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Mensaje recibido:', data);
};
```

## API

### `Hauyna::WebSocket::Handler`

- **Propiedades**:
  - `on_open` : Proc(HTTP::WebSocket, JSON::Any, Nil)
  - `on_message` : Proc(HTTP::WebSocket, JSON::Any, Nil)
  - `on_close` : Proc(HTTP::WebSocket, Nil)
  - `on_ping` : Proc(HTTP::WebSocket, String, Nil)
  - `on_pong` : Proc(HTTP::WebSocket, String, Nil)
  - `extract_identifier` : Proc(HTTP::WebSocket, JSON::Any, String?)

### `Hauyna::WebSocket::Router`

- **Métodos**:
  - `websocket(path : String, handler : Handler)` : Define una ruta de WebSocket
  - `call(context : HTTP::Server::Context) : Bool` : Procesa la solicitud WebSocket

### `Hauyna::WebSocket::Events`

- **Métodos**:
  - `on(event : String, &block)` : Registra un manejador de eventos
  - `trigger_event(event : String, socket, data)` : Dispara un evento registrado

## Ventajas

- API simple y clara
- Alto rendimiento
- Bajo consumo de memoria
- Escalable para múltiples conexiones
- Fácil integración con aplicaciones Crystal existentes
- Código limpio y bien documentado

## Contribución

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/amazing-feature`)
3. Commit tus cambios (`git commit -am 'Add some amazing feature'`)
4. Push a la rama (`git push origin feature/amazing-feature`)
5. Crea un Pull Request

¿Encontraste un bug? ¿Tienes una idea? ¡Abre un issue!

## Contribuidores

Hauyna WebSocket es una librería creada y mantenida por [José Antonio Padre García](https://github.com/Stockers-JAPG) y [Luis Antonio Padre García](https://github.com/LuisPadre25).
Agradecemos tus comentarios, reportes de errores y sugerencias para seguir mejorando esta herramienta.

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
        <img src="https://github.com/LuisPadre25.png" width="100px;" alt="José Antonio Padre García"/><br />
        <sub><b>Luis Antonio Padre García</b></sub>
      </a>
    </td>
  </tr>
</table>

## Licencia


**Hauyna** se distribuye bajo la [Licencia MIT](https://opensource.org/licenses/MIT).  
Siéntete libre de usarla en proyectos personales o comerciales.  
¡Aporta mejoras si lo deseas!

---

**¡Disfruta desarrollando aplicaciones WebSocket potentes y rápidas con Hauyna!**  
Si encuentras problemas o sugerencias, crea un _issue_ en el repositorio oficial.

## Características Destacadas

- 🚀 **API Simple y Flexible**: Diseñada para ser intuitiva y fácil de usar
- 👥 **Gestión de Grupos**: Agrupa usuarios y envía mensajes a grupos específicos
- 🔒 **Identificación de Usuarios**: Sistema integrado para identificar conexiones
- 📨 **Patrones de Mensajería**: Broadcast, mensajes privados y grupales
- 🎯 **Enrutamiento Simple**: Define rutas WebSocket fácilmente
- 🛡️ **Manejo de Errores**: Sistema robusto de manejo de errores y reconexión
- 📊 **Ejemplos Completos**: Múltiples ejemplos de implementación
- 🔄 **Eventos en Tiempo Real**: Sistema de eventos para actualizaciones instantáneas

[![GitHub release](https://img.shields.io/github/release/tu-usuario/hauyna-web-socket.svg)](https://github.com/tu-usuario/hauyna-web-socket/releases)
[![Build Status](https://github.com/tu-usuario/hauyna-web-socket/workflows/CI/badge.svg)](https://github.com/tu-usuario/hauyna-web-socket/actions)
[![License](https://img.shields.io/github/license/tu-usuario/hauyna-web-socket.svg)](https://github.com/tu-usuario/hauyna-web-socket/blob/master/LICENSE)
