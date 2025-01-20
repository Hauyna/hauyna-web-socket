require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de pizarra colaborativa con múltiples herramientas

class DrawAction
  include JSON::Serializable
  
  property tool : String # pen, eraser, rectangle, circle
  property color : String
  property size : Float64
  property points : Array(Hash(String, Float64))
  property user_id : String
  
  def initialize(@tool, @color, @size, @points, @user_id)
  end
end

class Whiteboard
  include JSON::Serializable
  
  property actions : Array(DrawAction)
  property users : Hash(String, String) # user_id => color
  
  COLORS = ["#ff0000", "#00ff00", "#0000ff", "#ff00ff", "#00ffff", "#ffff00"]
  
  def initialize
    @actions = [] of DrawAction
    @users = {} of String => String
  end
  
  def add_user(user_id : String)
    @users[user_id] = COLORS[@users.size % COLORS.size]
  end
  
  def add_action(action : DrawAction)
    @actions << action
  end
end

whiteboard = Whiteboard.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      whiteboard.add_user(user_id)
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
      
      socket.send({
        type: "init",
        whiteboard: whiteboard,
        your_color: whiteboard.users[user_id]
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if data["type"]?.try(&.as_s) == "draw"
          action = DrawAction.new(
            tool: data["tool"].as_s,
            color: data["color"].as_s,
            size: data["size"].as_f,
            points: data["points"].as_a.map { |p| {
              "x" => p["x"].as_f,
              "y" => p["y"].as_f
            }},
            user_id: user_id
          )
          
          whiteboard.add_action(action)
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "draw_update",
            action: action
          }.to_json)
        end
      rescue ex
        socket.send({
          type: "error",
          message: ex.message
        }.to_json)
      end
    end
  }

  router.websocket("/whiteboard", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Pizarra Colaborativa</title>
          <style>
            .container {
              display: flex;
              gap: 20px;
              padding: 20px;
            }
            #canvas {
              border: 1px solid #ccc;
              cursor: crosshair;
            }
            .toolbar {
              display: flex;
              flex-direction: column;
              gap: 10px;
            }
            .tool {
              padding: 10px;
              border: 1px solid #ccc;
              cursor: pointer;
            }
            .tool.active {
              background: #e0e0e0;
            }
            #size {
              width: 100%;
            }
            .users {
              margin-top: 20px;
            }
            .user {
              display: flex;
              align-items: center;
              gap: 5px;
            }
            .color-dot {
              width: 10px;
              height: 10px;
              border-radius: 50%;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="toolbar">
              <div class="tool active" data-tool="pen">Lápiz</div>
              <div class="tool" data-tool="eraser">Borrador</div>
              <div class="tool" data-tool="rectangle">Rectángulo</div>
              <div class="tool" data-tool="circle">Círculo</div>
              <input type="range" id="size" min="1" max="20" value="2">
              <div class="users" id="users"></div>
            </div>
            <canvas id="canvas" width="800" height="600"></canvas>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/whiteboard?user_id=\${userId}\`);
            const canvas = document.getElementById('canvas');
            const ctx = canvas.getContext('2d');
            const tools = document.querySelectorAll('.tool');
            let currentTool = 'pen';
            let isDrawing = false;
            let currentColor = '#000000';
            let startPoint = null;
            let points = [];

            // Limpiar el canvas
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            tools.forEach(tool => {
              tool.onclick = () => {
                tools.forEach(t => t.classList.remove('active'));
                tool.classList.add('active');
                currentTool = tool.dataset.tool;
              };
            });

            function drawAction(action) {
              if (!action || !action.points || action.points.length === 0) return;
              
              ctx.beginPath();
              ctx.strokeStyle = action.color;
              ctx.lineWidth = action.size;
              
              switch(action.tool) {
                case 'pen':
                case 'eraser':
                  const strokeStyle = action.tool === 'eraser' ? '#ffffff' : action.color;
                  ctx.strokeStyle = strokeStyle;
                  ctx.beginPath();
                  ctx.moveTo(action.points[0].x, action.points[0].y);
                  action.points.forEach(point => {
                    ctx.lineTo(point.x, point.y);
                  });
                  ctx.stroke();
                  break;
                  
                case 'rectangle':
                  const [start, end] = action.points;
                  const width = end.x - start.x;
                  const height = end.y - start.y;
                  ctx.strokeRect(start.x, start.y, width, height);
                  break;
                  
                case 'circle':
                  const [center, edge] = action.points;
                  const radius = Math.sqrt(
                    Math.pow(edge.x - center.x, 2) +
                    Math.pow(edge.y - center.y, 2)
                  );
                  ctx.beginPath();
                  ctx.arc(center.x, center.y, radius, 0, Math.PI * 2);
                  ctx.stroke();
                  break;
              }
            }

            function updateUsers(whiteboard) {
              const usersDiv = document.getElementById('users');
              usersDiv.innerHTML = Object.entries(whiteboard.users)
                .map(([id, color]) => \`
                  <div class="user">
                    <div class="color-dot" style="background: \${color}"></div>
                    \${id === userId ? 'Tú' : id}
                  </div>
                \`).join('');
            }

            function drawPreview(e) {
              if (!isDrawing) return;
              
              const currentPoint = {
                x: parseFloat(e.offsetX),
                y: parseFloat(e.offsetY)
              };

              // Crear una copia temporal del canvas
              const tempCanvas = document.createElement('canvas');
              tempCanvas.width = canvas.width;
              tempCanvas.height = canvas.height;
              const tempCtx = tempCanvas.getContext('2d');
              tempCtx.drawImage(canvas, 0, 0);

              // Dibujar la vista previa
              tempCtx.beginPath();
              tempCtx.strokeStyle = currentColor;
              tempCtx.lineWidth = parseFloat(document.getElementById('size').value);

              if (['rectangle', 'circle'].includes(currentTool)) {
                if (currentTool === 'rectangle') {
                  const width = currentPoint.x - startPoint.x;
                  const height = currentPoint.y - startPoint.y;
                  tempCtx.strokeRect(startPoint.x, startPoint.y, width, height);
                } else {
                  const radius = Math.sqrt(
                    Math.pow(currentPoint.x - startPoint.x, 2) +
                    Math.pow(currentPoint.y - startPoint.y, 2)
                  );
                  tempCtx.beginPath();
                  tempCtx.arc(startPoint.x, startPoint.y, radius, 0, Math.PI * 2);
                  tempCtx.stroke();
                }
              }
            }

            canvas.addEventListener('mousedown', (e) => {
              isDrawing = true;
              startPoint = {
                x: parseFloat(e.offsetX),
                y: parseFloat(e.offsetY)
              };
              points = [startPoint];

              if (['pen', 'eraser'].includes(currentTool)) {
                ctx.beginPath();
                ctx.moveTo(startPoint.x, startPoint.y);
              }
            });

            canvas.addEventListener('mousemove', (e) => {
              if (!isDrawing) return;
              
              const currentPoint = {
                x: parseFloat(e.offsetX),
                y: parseFloat(e.offsetY)
              };
              
              if (['pen', 'eraser'].includes(currentTool)) {
                points.push(currentPoint);
                ws.send(JSON.stringify({
                  type: 'draw',
                  tool: currentTool,
                  color: currentColor,
                  size: parseFloat(document.getElementById('size').value),
                  points: points.slice(-2)
                }));
              } else {
                drawPreview(e);
              }
            });

            canvas.addEventListener('mouseup', () => {
              if (!isDrawing) return;
              
              if (['rectangle', 'circle'].includes(currentTool)) {
                const endPoint = points[points.length - 1];
                ws.send(JSON.stringify({
                  type: 'draw',
                  tool: currentTool,
                  color: currentColor,
                  size: parseFloat(document.getElementById('size').value),
                  points: [startPoint, endPoint]
                }));
              }
              
              isDrawing = false;
              startPoint = null;
            });

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  currentColor = data.your_color;
                  updateUsers(data.whiteboard);
                  if (data.whiteboard.actions) {
                    data.whiteboard.actions.forEach(drawAction);
                  }
                  break;
                  
                case 'draw_update':
                  drawAction(data.action);
                  break;
                  
                case 'error':
                  console.error(data.message);
                  break;
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