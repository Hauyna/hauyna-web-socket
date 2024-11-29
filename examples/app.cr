require "./../src/hauyna-web-socket.cr"


require "http"

# Para almacenar las conexiones de los clientes
clients = [] of HTTP::WebSocket

# Crear el router WebSocket
router = Hauyna::WebSocket::Router.new
handler = Hauyna::WebSocket::Handler.new(
  on_open: -> (socket: HTTP::WebSocket) do
    Hauyna::WebSocket::Events.trigger_event("user_joined", socket, {"username" => "juan"})
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

Hauyna::WebSocket::Events.on("user_joined") do |socket, data|
    puts "Nuevo usuario unido: #{data["username"]}"
  end

# Vinculamos el servidor en la IP y puerto especificados
address = server.bind_tcp "0.0.0.0", 8080
puts "Servidor escuchando en http://#{address}"

# Escuchar peticiones entrantes
server.listen