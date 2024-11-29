require "http/server"
require "./../../src/opal-web-socket"

# Para almacenar las conexiones de los clientes
clients = [] of HTTP::WebSocket

# Crear el router WebSocket
router = Hauyna::WebSocket::Router.new

router.websocket "/chat", Hauyna::WebSocket::Handler.new(
  on_open: ->(socket : HTTP::WebSocket) do
    # Cuando un nuevo cliente se conecta, lo agregamos a la lista
    clients << socket
    puts "Cliente conectado: #{socket}"
  end,

  on_message: ->(socket : HTTP::WebSocket, message : String) do
    if message.downcase == "ping"
      # Si el mensaje es un ping de aplicación, responder con pong
      socket.send("pong")
      puts "Recibido 'ping' de cliente: #{socket}"
    else
      # Retransmitimos el mensaje a todos los clientes conectados
      clients.each do |client|
        # Evitar enviar el mensaje al mismo cliente que lo envió
        client.send(message) unless client == socket
      end
      puts "Mensaje recibido de #{socket}: #{message}"
    end
  end,

  on_close: ->(socket : HTTP::WebSocket) do
    clients.delete(socket)
    puts "Cliente desconectado: #{socket}"
  end,

  # Opcional: Manejar frames de control WebSocket (automáticamente gestionados)
  on_ping: ->(socket : HTTP::WebSocket, message : String) do
    puts "Recibido PING: #{message}"
    socket.pong("Respuesta al PING")
  end,
  # on_pong: ->(socket : HTTP::WebSocket, message : String) do
  #   puts "Recibido PONG: #{message}"
  # end
)

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
