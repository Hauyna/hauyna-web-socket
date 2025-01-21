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

### Prerequisitos

- Crystal 1.0 o superior
- Git (opcional)

### Desde Crystal Shards

1. Agrega la dependencia a tu `shard.yml`:

```yaml
dependencies:
  hauyna-web-socket:
    github: Stockers-JAPG/hauyna-web-socket
    version: ~> 0.1.0
```

2. Instala las dependencias:

```bash
shards install
```

### Desde el Código Fuente

1. Clona el repositorio:

```bash
git clone https://github.com/Stockers-JAPG/hauyna-web-socket.git
```

2. Entra al directorio:

```bash
cd hauyna-web-socket
```

3. Compila e instala:

```bash
shards build
```

## Uso Básico

```crystal
require "http"
require "hauyna-web-socket"

# Crear un manejador WebSocket
handler = Hauyna::WebSocket::Handler.new(
  on_open: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    puts "Nueva conexión establecida"
  },
  
  on_message: ->(socket : HTTP::WebSocket, message : String) {
    puts "Mensaje recibido: #{message}"
  },

  on_close: ->(socket : HTTP::WebSocket) {
    puts "Conexión cerrada"
  }
)

# Configurar el router
router = Hauyna::WebSocket::Router.new
router.websocket("/chat", handler)

# Iniciar el servidor
server = HTTP::Server.new do |context|
  router.call(context)
end

server.listen("0.0.0.0", 3000)
```

### Manejo de Eventos Personalizados

```crystal
# Registrar un evento
Hauyna::WebSocket::Events.on("user_joined") do |socket, data|
  puts "Nuevo usuario unido: #{data["username"]}"
end

# Disparar un evento
Hauyna::WebSocket::Events.trigger_event("user_joined", socket, {"username" => "juan"})
```

### Definir Rutas Dinámicas

```crystal
# Ruta con parámetros dinámicos
router.websocket("/user/:id", handler)

# Acceder a los parámetros
route = router.websocket_routes.first
params = route.params("/user/123")
puts "ID de usuario: #{params["id"]}"
```

## API

### `Hauyna::WebSocket::Handler`

- **Propiedades**:
  - `on_open_callback` : Callback para el evento de apertura de conexión
  - `on_message_callback` : Callback para recibir mensajes
  - `on_close_callback` : Callback para el evento de cierre de conexión
  - `on_ping_callback` : Callback para manejar mensajes ping
  - `on_pong_callback` : Callback para manejar mensajes pong

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
2. Crea tu rama de características (`git checkout -b mi-nueva-caracteristica`)
3. Commit tus cambios (`git commit -am 'Agrega alguna característica'`)
4. Push a la rama (`git push origin mi-nueva-caracteristica`)
5. Crea un nuevo Pull Request


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
