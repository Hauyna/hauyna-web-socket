require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de dibujo colaborativo en tiempo real

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  handler = Hauyna::WebSocket::Handler.new(
    extract_identifier: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      params["user_id"]?.try(&.as_s)
    },

    on_open: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      if user_id = params["user_id"]?.try(&.as_s)
        room = params["room"]?.try(&.as_s) || "default"
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, room)
        Hauyna::WebSocket::Events.send_to_group(room, {
          type: "user_joined",
          user_id: user_id
        }.to_json)
      end
    },

    on_message: ->(socket : HTTP::WebSocket, message : String) {
      if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        data = JSON.parse(message)
        room = data["room"]?.try(&.as_s) || "default"
        # Reenviar el trazo a todos los usuarios en la sala
        Hauyna::WebSocket::Events.send_to_group(room, {
          type: "draw",
          user_id: user_id,
          data: data
        }.to_json)
      end
    },

    on_close: ->(socket : HTTP::WebSocket) {
      if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        Hauyna::WebSocket::Events.broadcast({
          type: "user_left",
          user_id: user_id
        }.to_json)
      end
    }
  )

  router.websocket("/draw", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Dibujo Colaborativo</title>
          <style>
            #canvas {
              border: 1px solid #ccc;
              cursor: crosshair;
            }
            .controls {
              margin: 10px 0;
            }
            .color-picker {
              margin-right: 10px;
            }
          </style>
        </head>
        <body>
          <div class="controls">
            <input type="color" id="colorPicker" class="color-picker">
            <input type="range" id="brushSize" min="1" max="20" value="5">
            <button onclick="clearCanvas()">Limpiar</button>
            <span id="status">Conectando...</span>
          </div>
          <canvas id="canvas" width="800" height="600"></canvas>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(`ws://localhost:8080/draw?user_id=${userId}`);
            const canvas = document.getElementById('canvas');
            const ctx = canvas.getContext('2d');
            const status = document.getElementById('status');
            const colorPicker = document.getElementById('colorPicker');
            const brushSize = document.getElementById('brushSize');
            
            let isDrawing = false;
            let lastX = 0;
            let lastY = 0;

            ctx.lineCap = 'round';
            ctx.lineJoin = 'round';

            function draw(e) {
              if (!isDrawing) return;
              
              const rect = canvas.getBoundingClientRect();
              const x = e.clientX - rect.left;
              const y = e.clientY - rect.top;
              
              ctx.beginPath();
              ctx.moveTo(lastX, lastY);
              ctx.lineTo(x, y);
              ctx.strokeStyle = colorPicker.value;
              ctx.lineWidth = brushSize.value;
              ctx.stroke();
              
              ws.send(JSON.stringify({
                type: 'line',
                from: { x: lastX, y: lastY },
                to: { x, y },
                color: colorPicker.value,
                size: brushSize.value
              }));
              
              [lastX, lastY] = [x, y];
            }

            canvas.addEventListener('mousedown', (e) => {
              isDrawing = true;
              const rect = canvas.getBoundingClientRect();
              [lastX, lastY] = [e.clientX - rect.left, e.clientY - rect.top];
            });

            canvas.addEventListener('mousemove', draw);
            canvas.addEventListener('mouseup', () => isDrawing = false);
            canvas.addEventListener('mouseout', () => isDrawing = false);

            function clearCanvas() {
              ctx.clearRect(0, 0, canvas.width, canvas.height);
              ws.send(JSON.stringify({ type: 'clear' }));
            }

            ws.onopen = () => {
              status.textContent = 'Conectado';
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              if (data.type === 'draw' && data.data.type === 'line') {
                const line = data.data;
                ctx.beginPath();
                ctx.moveTo(line.from.x, line.from.y);
                ctx.lineTo(line.to.x, line.to.y);
                ctx.strokeStyle = line.color;
                ctx.lineWidth = line.size;
                ctx.stroke();
              } else if (data.type === 'draw' && data.data.type === 'clear') {
                ctx.clearRect(0, 0, canvas.width, canvas.height);
              }
            };
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 