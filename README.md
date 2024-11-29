
# Hauyna WebSocket

Hauyna WebSocket es una librería ligera para manejar conexiones WebSocket en Crystal. Ofrece una API sencilla para definir rutas de WebSocket, manejar eventos y establecer callbacks personalizados para eventos como `on_open`, `on_message`, `on_close`, entre otros.

## Características

- **Gestión de WebSockets**: Establece y gestiona conexiones WebSocket de manera eficiente.
- **Rutas de WebSocket**: Define rutas personalizadas para manejar diferentes endpoints de WebSocket.
- **Eventos Personalizados**: Registra y dispara eventos WebSocket de forma sencilla.
- **Callbacks Personalizados**: Control total sobre los eventos de WebSocket como apertura, cierre, mensajes, ping/pong, etc.

## Instalación

1. Agrega la librería a tu proyecto Crystal agregando la dependencia en el archivo `shard.yml` de tu proyecto:

```yaml
dependencies:
  hauyna-web-socket:
    github: Stockers-JAPG/hauyna-web-socket
    version: ~> 0.1.0
```

2. Ejecuta `shards install` para instalar la librería.

## Uso

### Crear un servidor WebSocket

Primero, necesitas crear un `Handler` que maneje los eventos de WebSocket como la apertura de la conexión, la recepción de mensajes, el cierre, etc.

```crystal
require "http"
require "hauyna-web-socket"

# Para almacenar las conexiones de los clientes
clients = [] of HTTP::WebSocket

# Crear el router WebSocket
router = Hauyna::WebSocket::Router.new
handler = Hauyna::WebSocket::Handler.new(
  on_open: -> (socket: HTTP::WebSocket) do
    puts "Conexión abierta: #{socket}"
  end,
  on_message: -> (socket: HTTP::WebSocket, message: String) do
    puts "Mensaje recibido: #{message}"
  end,
  on_close: -> (socket: HTTP::WebSocket) do
    puts "Conexión cerrada: #{socket}"
  end,
  on_ping: -> (socket: HTTP::WebSocket, message: String) do
    puts "Ping recibido: #{message}"
  end
)

router.websocket "/chat", handler

# Configuración del servidor HTTP
server = HTTP::Server.new do |context|
  if router.call(context)
    # La solicitud fue manejada por el router WebSocket
  else
    context.response.content_type = "text/plain"
    context.response.print "Ruta no encontrada"
  end
end

# Vinculamos el servidor en la IP y puerto especificados
address = server.bind_tcp "0.0.0.0", 8080
puts "Servidor escuchando en http://#{address}"

# Escuchar peticiones entrantes
server.listen

```

### Ejemplo de Envío de Mensajes

Dentro del callback `on_message`, puedes enviar mensajes a los clientes conectados utilizando el objeto `socket`.

```crystal
handler = Hauyna::WebSocket::Handler.new(
  on_message: { |socket, message|
    puts "Mensaje recibido: #{message}"
    # Enviar una respuesta al cliente
    socket.send "Mensaje procesado: #{message}"
  }
)
```

### Manejo de Eventos Personalizados

Puedes registrar eventos personalizados en la librería `Hauyna::WebSocket::Events` y dispararlos desde cualquier parte de tu código.

#### Registrar un evento

```crystal
Hauyna::WebSocket::Events.on("user_joined") do |socket, data|
  puts "Nuevo usuario unido: #{data["username"]}"
end
```

#### Disparar un evento

```crystal
Hauyna::WebSocket::Events.trigger_event("user_joined", socket, {"username" => "juan"})
```

### Definir Rutas Dinámicas

Las rutas de WebSocket pueden incluir parámetros dinámicos. Por ejemplo, la siguiente ruta captura un ID de usuario como parámetro.

```crystal
router.websocket("/user/:id", handler)
```

Puedes acceder al parámetro en el `Handler` utilizando el método `params` en `WebSocketRoute`.

```crystal
route = router.websocket_routes.first
params = route.params("/user/123")
puts "ID de usuario: #{params["id"]}"
```

## API

### `Hauyna::WebSocket::Handler`

- **Propiedades**:
  - `on_open_callback` : `Proc(HTTP::WebSocket, Nil)?` — Callback para el evento de apertura de conexión.
  - `on_message_callback` : `Proc(HTTP::WebSocket, String, Nil)?` — Callback para recibir mensajes.
  - `on_close_callback` : `Proc(HTTP::WebSocket, Nil)?` — Callback para el evento de cierre de conexión.
  - `on_ping_callback` : `Proc(HTTP::WebSocket, String, Nil)?` — Callback para manejar mensajes ping.
  - `on_pong_callback` : `Proc(HTTP::WebSocket, String, Nil)?` — Callback para manejar mensajes pong.

- **Métodos**:
  - `on_open(socket : HTTP::WebSocket)` — Ejecuta el callback de apertura.
  - `on_message(socket : HTTP::WebSocket, message : String)` — Ejecuta el callback para mensajes.
  - `on_close(socket : HTTP::WebSocket)` — Ejecuta el callback de cierre.
  - `on_ping(socket : HTTP::WebSocket, message : String)` — Ejecuta el callback de ping.
  - `on_pong(socket : HTTP::WebSocket, message : String)` — Ejecuta el callback de pong.

### `Hauyna::WebSocket::Router`

- **Propiedades**:
  - `websocket_routes` : `Array(WebSocketRoute)` — Lista de rutas de WebSocket.

- **Métodos**:
  - `websocket(path : String, handler : Handler)` — Define una ruta de WebSocket con su respectivo handler.
  - `call(context : HTTP::Server::Context) : Bool` — Llama al router para determinar si una solicitud es un WebSocket y ejecuta el handler correspondiente.

### `Hauyna::WebSocket::WebSocketRoute`

- **Propiedades**:
  - `path` : `String` — La ruta de WebSocket.
  - `handler` : `Handler` — El handler que maneja la ruta.
  - `segments` : `Array(String)` — Segmentos de la ruta, incluyendo parámetros dinámicos.

- **Métodos**:
  - `match?(request_path : String) : Bool` — Verifica si la ruta coincide con la solicitud.
  - `params(request_path : String) : Hash(String, String)` — Extrae los parámetros de la ruta.

### `Hauyna::WebSocket::Events`

- **Métodos**:
  - `on(event_name : String, &block : Proc(HTTP::WebSocket, JSON::Any, Nil))` — Registra un manejador de eventos.
  - `trigger_event(event_name : String, socket : HTTP::WebSocket, data : JSON::Any)` — Dispara un evento registrado.

## Contribuir

Si deseas contribuir a esta librería, siéntete libre de abrir un pull request o reportar problemas en la sección de [Issues](https://github.com/tu_usuario/hauyna-web-socket/issues).

### Licencia

Este proyecto está bajo la licencia MIT. Consulta el archivo `LICENSE` para más detalles.


