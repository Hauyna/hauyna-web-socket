# Handler API

El Handler maneja las conexiones WebSocket y sus eventos.

## Inicialización

```crystal
def initialize(
  @on_open = nil,
  @on_message = nil,
  @on_close = nil,
  @on_ping = nil,
  @on_pong = nil,
  @extract_identifier = nil,
  heartbeat_interval : Time::Span? = nil,
  heartbeat_timeout : Time::Span? = nil,
  @read_timeout : Int32 = 30,
  @write_timeout : Int32 = 30
)
```

## Callbacks

### on_open
```crystal
property on_open : Proc(HTTP::WebSocket, JSON::Any, Nil)?
```
Llamado cuando se establece una nueva conexión.

### on_message
```crystal
property on_message : Proc(HTTP::WebSocket, JSON::Any, Nil)?
```
Llamado cuando se recibe un mensaje.

### on_close
```crystal
property on_close : Proc(HTTP::WebSocket, Nil)?
```
Llamado cuando se cierra la conexión.

## Ejemplo

```crystal
handler = Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "User ID required"
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Nueva conexión: #{params["user_id"]}"
  },
  
  heartbeat_interval: 30.seconds
)
``` 