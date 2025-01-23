require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de un chat simple usando Hauyna WebSocket

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  # Crear un manejador para el WebSocket
  handler = Hauyna::WebSocket::Handler.new(
    # Extraer el identificador del usuario de los parámetros
    extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      params["username"]?.try(&.as_s)
    },

    # Manejar cuando un usuario se conecta
    on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      username = params["username"]?.try(&.as_s) || "Anónimo"
      Hauyna::WebSocket::Events.broadcast("#{username} se ha conectado")
    },

    # Manejar los mensajes recibidos
    on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
      if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        Hauyna::WebSocket::Events.broadcast("#{identifier}: #{data.as_s}")
      end
    },

    # Manejar cuando un usuario se desconecta
    on_close: ->(socket : HTTP::WebSocket) {
      if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        Hauyna::WebSocket::Events.broadcast("#{identifier} se ha desconectado")
      end
    }
  )

  # Registrar la ruta del WebSocket
  router.websocket("/chat", handler)
  
  # Intentar manejar la conexión WebSocket
  next if router.call(context)

  # Si no es una solicitud WebSocket, servir el HTML
  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Chat Simple</title>
        </head>
        <body>
          <div id="messages" style="height: 400px; overflow-y: scroll; border: 1px solid #ccc; padding: 10px;"></div>
          <input type="text" id="messageInput" placeholder="Escribe un mensaje...">
          <button onclick="sendMessage()">Enviar</button>

          <script>
            const username = prompt('Ingresa tu nombre de usuario:') || 'Anónimo';
            const ws = new WebSocket(`ws://localhost:8080/chat?username=${encodeURIComponent(username)}`);
            const messages = document.getElementById('messages');
            const messageInput = document.getElementById('messageInput');

            ws.onmessage = (event) => {
              const div = document.createElement('div');
              div.textContent = event.data;
              messages.appendChild(div);
              messages.scrollTop = messages.scrollHeight;
            };

            function sendMessage() {
              const message = messageInput.value;
              if (message.trim()) {
                ws.send(message);
                messageInput.value = '';
              }
            }

            messageInput.addEventListener('keypress', (e) => {
              if (e.key === 'Enter') sendMessage();
            });
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 