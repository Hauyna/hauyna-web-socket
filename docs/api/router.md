# Router API

El Router maneja el enrutamiento de conexiones WebSocket.

## Métodos Principales

### websocket
```crystal
def websocket(path : String, handler : Handler)
```
Registra una ruta WebSocket con su manejador.

### call
```crystal
def call(context : HTTP::Server::Context) : Bool
```
Procesa una solicitud HTTP/WebSocket.

## Ejemplo

```crystal
router = Router.new

# Registrar rutas
router.websocket "/chat", chat_handler
router.websocket "/notifications", notification_handler

# Usar en servidor HTTP
server = HTTP::Server.new do |context|
  router.call(context)
end
``` 