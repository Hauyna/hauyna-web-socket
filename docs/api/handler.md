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

## Configuración de Timeouts

```crystal
@read_timeout : Int32 = 30  # Timeout de lectura en segundos
@write_timeout : Int32 = 30 # Timeout de escritura en segundos
```

## Heartbeat

El Handler puede configurarse con un heartbeat para mantener las conexiones activas:

```crystal
handler = Handler.new(
  heartbeat_interval: 30.seconds,
  heartbeat_timeout: 60.seconds
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

### on_ping
```crystal
property on_ping : Proc(HTTP::WebSocket, String, Nil)?
```
Llamado cuando se recibe un ping.

### on_pong
```crystal
property on_pong : Proc(HTTP::WebSocket, String, Nil)?
```
Llamado cuando se recibe un pong.

## Ejemplo

```crystal
handler = Handler.new(
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String {
    params["user_id"]?.try(&.as_s) || raise "User ID required"
  },
  
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    puts "Nueva conexión: #{params["user_id"]}"
  },
  
  heartbeat_interval: 30.seconds,
  read_timeout: 60,
  write_timeout: 60
)
``` 