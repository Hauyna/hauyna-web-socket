require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de chat con grupos usando Hauyna WebSocket

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  handler = Hauyna::WebSocket::Handler.new(
    extract_identifier: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      params["username"]?.try(&.as_s)
    },

    on_open: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      if username = params["username"]?.try(&.as_s)
        # Añadir usuario a ambas salas al conectarse
        ["general", "news"].each do |room|
          Hauyna::WebSocket::ConnectionManager.add_to_group(username, room)
          Hauyna::WebSocket::Events.send_to_group(room, "Usuario #{username} se ha unido a la sala #{room}")
        end
      end
    },

    on_message: ->(socket : HTTP::WebSocket, message : String) {
      if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        begin
          data = JSON.parse(message)
          room = data["room"].as_s
          content = data["message"].as_s
          # Enviar el mensaje con el formato correcto para que coincida con la lógica del cliente
          Hauyna::WebSocket::Events.send_to_group(room, "[Sala #{room}] #{identifier}: #{content}")
        rescue ex
          socket.send("Error: Formato de mensaje inválido - #{ex.message}")
        end
      end
    },

    on_close: ->(socket : HTTP::WebSocket) {
      if identifier = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        Hauyna::WebSocket::Events.broadcast("#{identifier} se ha desconectado")
      end
    }
  )

  router.websocket("/groupchat", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Chat Grupal</title>
          <style>
            .chat-container { display: flex; gap: 20px; }
            .room { width: 300px; border: 1px solid #ccc; padding: 10px; }
            .messages { height: 300px; overflow-y: scroll; margin-bottom: 10px; }
          </style>
        </head>
        <body>
          <div class="chat-container">
            <div class="room">
              <h3>Sala General</h3>
              <div id="general-messages" class="messages"></div>
              <input type="text" id="general-input" placeholder="Mensaje para Sala General">
              <button onclick="sendMessage('general')">Enviar</button>
            </div>
            
            <div class="room">
              <h3>Sala Noticias</h3>
              <div id="news-messages" class="messages"></div>
              <input type="text" id="news-input" placeholder="Mensaje para Sala Noticias">
              <button onclick="sendMessage('news')">Enviar</button>
            </div>
          </div>

          <script>
            const username = prompt('Ingresa tu nombre de usuario:') || 'Anónimo';
            const ws = new WebSocket(`ws://localhost:8080/groupchat?username=${encodeURIComponent(username)}&room=general`);
            
            ws.onopen = () => {
              // Unirse a ambas salas
              ws.send(JSON.stringify({ room: 'general', message: 'join' }));
              ws.send(JSON.stringify({ room: 'news', message: 'join' }));
            };

            ws.onmessage = (event) => {
              const message = event.data;
              if (message.includes('[Sala general]')) {
                appendMessage('general-messages', message);
              } else if (message.includes('[Sala news]')) {
                appendMessage('news-messages', message);
              } else {
                // Para mensajes del sistema
                appendMessage('general-messages', message);
                appendMessage('news-messages', message);
              }
            };

            function appendMessage(elementId, message) {
              const div = document.createElement('div');
              div.textContent = message;
              document.getElementById(elementId).appendChild(div);
            }

            function sendMessage(room) {
              const input = document.getElementById(`${room}-input`);
              const message = input.value.trim();
              if (message) {
                ws.send(JSON.stringify({ room, message }));
                input.value = '';
              }
            }
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 