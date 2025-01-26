require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de notificaciones usando Hauyna WebSocket

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  handler = Hauyna::WebSocket::Handler.new(
    extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      params["user_id"]?.try(&.as_s)
    },

    on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      if user_id = params["user_id"]?.try(&.as_s)
        # Añadir usuario a su grupo personal para notificaciones dirigidas
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "user_#{user_id}")
        # Añadir usuario al grupo de notificaciones generales
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "general_notifications")

        socket.send(JSON.build { |json|
          json.object do
            json.field "type", "connected"
            json.field "user_id", user_id
          end
        })
      end
    }
  )

  router.websocket("/notifications", handler)

  next if router.call(context)

  case context.request.path
  when "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Sistema de Notificaciones</title>
          <style>
            #notifications {
              position: fixed;
              top: 20px;
              right: 20px;
              width: 300px;
            }
            .notification {
              background: #f0f0f0;
              border: 1px solid #ccc;
              padding: 10px;
              margin-bottom: 10px;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
          <h1>Sistema de Notificaciones</h1>
          <div>
            <button onclick="sendGeneralNotification()">Enviar Notificación General</button>
            <input type="text" id="userIdInput" placeholder="ID de usuario">
            <button onclick="sendUserNotification()">Enviar Notificación a Usuario</button>
          </div>
          <div id="notifications"></div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            console.log("Tu ID de usuario es:", userId); // Añadir esto para ver el ID
            const ws = new WebSocket(`ws://localhost:8080/notifications?user_id=${userId}`);
            
            ws.onmessage = (event) => {
              const notification = document.createElement('div');
              notification.className = 'notification';
              notification.textContent = event.data;
              document.getElementById('notifications').prepend(notification);
              
              // Eliminar la notificación después de 5 segundos
              setTimeout(() => notification.remove(), 5000);
            };

            async function sendGeneralNotification() {
              try {
                const response = await fetch('/send-general', { 
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' }
                });
                const data = await response.json();
                console.log('Notificación general enviada:', data);
              } catch (error) {
                console.error('Error al enviar notificación general:', error);
              }
            }

            async function sendUserNotification() {
              const targetUserId = document.getElementById('userIdInput').value;
              if (!targetUserId) {
                alert('Por favor, ingresa un ID de usuario');
                return;
              }
              try {
                const response = await fetch('/send-user', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ userId: targetUserId })
                });
                const data = await response.json();
                console.log('Notificación personal enviada:', data);
              } catch (error) {
                console.error('Error al enviar notificación personal:', error);
              }
            }
          </script>
        </body>
      </html>
    HTML
  when "/send-general"
    if context.request.method == "POST"
      notification = "Notificación general: #{Time.local}"
      Hauyna::WebSocket::Events.send_to_group("general_notifications", notification)
      context.response.headers["Content-Type"] = "application/json"
      context.response.print "{\"status\": \"ok\", \"message\": \"#{notification}\"}"
    end
  when "/send-user"
    if context.request.method == "POST"
      if body = context.request.body
        begin
          payload = JSON.parse(body)
          user_id = payload["userId"].as_s
          notification = "Notificación personal para #{user_id}: #{Time.local}"
          Hauyna::WebSocket::Events.send_to_group("user_#{user_id}", notification)
          context.response.headers["Content-Type"] = "application/json"
          context.response.print "{\"status\": \"ok\", \"message\": \"#{notification}\"}"
        rescue ex
          context.response.status_code = 400
          context.response.headers["Content-Type"] = "application/json"
          context.response.print "{\"status\": \"error\", \"message\": \"#{ex.message}\"}"
        end
      end
    end
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
