require "../src/hauyna-web-socket"
require "http/server"

# Sistema de dibujo colaborativo con pizarra infinita

class Point
  include JSON::Serializable
  
  property x : Float64
  property y : Float64
  
  def initialize(@x, @y)
  end
end

class DrawCommand
  include JSON::Serializable
  
  property type : String # stroke, erase, shape
  property points : Array(Point)
  property color : String
  property size : Float64
  property user_id : String
  property shape_type : String? # circle, rectangle, line
  
  def initialize(@type, @points, @color, @size, @user_id, @shape_type = nil)
  end
end

class Canvas
  include JSON::Serializable
  
  property commands : Array(DrawCommand)
  property users : Hash(String, String) # user_id => name
  property viewport : Hash(String, Float64) # user_id => {x, y, zoom}
  
  COLORS = ["#ff0000", "#00ff00", "#0000ff", "#ff00ff", "#00ffff"]
  
  def initialize
    @commands = [] of DrawCommand
    @users = {} of String => String
    @viewport = {} of String => Float64
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
    @viewport[id] = 1.0 # zoom inicial
  end
  
  def add_command(command : DrawCommand)
    @commands << command
  end
  
  def update_viewport(user_id : String, x : Float64, y : Float64, zoom : Float64)
    @viewport[user_id] = zoom
  end
end

canvas = Canvas.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        canvas.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
        
        socket.send({
          type: "init",
          canvas: canvas
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "draw"
          command = DrawCommand.new(
            type: data["command_type"].as_s,
            points: data["points"].as_a.map { |p| Point.new(p["x"].as_f, p["y"].as_f) },
            color: data["color"].as_s,
            size: data["size"].as_f,
            user_id: user_id,
            shape_type: data["shape_type"]?.try(&.as_s)
          )
          canvas.add_command(command)
          
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "draw_update",
            command: command
          }.to_json)
          
        when "viewport"
          canvas.update_viewport(
            user_id,
            data["x"].as_f,
            data["y"].as_f,
            data["zoom"].as_f
          )
          
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "viewport_update",
            user_id: user_id,
            viewport: {
              x: data["x"].as_f,
              y: data["y"].as_f,
              zoom: data["zoom"].as_f
            }
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

  router.websocket("/canvas", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Pizarra Infinita</title>
          <style>
            body { margin: 0; overflow: hidden; }
            .container {
              position: fixed;
              top: 0;
              left: 0;
              width: 100vw;
              height: 100vh;
            }
            #canvas {
              position: absolute;
              top: 0;
              left: 0;
              cursor: crosshair;
            }
            .toolbar {
              position: fixed;
              top: 20px;
              left: 20px;
              background: white;
              padding: 10px;
              border-radius: 4px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            .tool {
              padding: 5px 10px;
              margin: 2px;
              cursor: pointer;
              border: 1px solid #ccc;
              border-radius: 3px;
            }
            .tool.active {
              background: #e3f2fd;
            }
            .users {
              position: fixed;
              top: 20px;
              right: 20px;
              background: white;
              padding: 10px;
              border-radius: 4px;
              box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            .user {
              display: flex;
              align-items: center;
              gap: 5px;
              margin: 5px 0;
            }
            .color-dot {
              width: 10px;
              height: 10px;
              border-radius: 50%;
            }
          </style>
        </head>
        <body>
          <div id="join" style="text-align: center; margin-top: 20px;">
            <h2>Unirse al Canvas</h2>
            <input type="text" id="name" placeholder="Tu nombre">
            <button onclick="joinCanvas()">Entrar</button>
          </div>
          
          <div id="canvas-container" class="container" style="display: none;">
            <canvas id="canvas"></canvas>
            <div class="toolbar">
              <button class="tool active" data-tool="pen">Lápiz</button>
              <button class="tool" data-tool="eraser">Borrador</button>
              <button class="tool" data-tool="line">Línea</button>
              <button class="tool" data-tool="rectangle">Rectángulo</button>
              <button class="tool" data-tool="circle">Círculo</button>
              <input type="range" id="size" min="1" max="20" value="2">
              <input type="color" id="color" value="#000000">
            </div>
            <div class="users" id="users"></div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let canvas;
            let ctx;
            let isDrawing = false;
            let currentTool = 'pen';
            let startPoint = null;
            let lastPoint = null;
            let viewportX = 0;
            let viewportY = 0;
            let zoom = 1;
            let isDragging = false;
            let dragStart = { x: 0, y: 0 };
            
            function initCanvas() {
              canvas = document.getElementById('canvas');
              ctx = canvas.getContext('2d');
              
              function resizeCanvas() {
                canvas.width = window.innerWidth;
                canvas.height = window.innerHeight;
                redraw();
              }
              
              window.addEventListener('resize', resizeCanvas);
              resizeCanvas();
              
              canvas.addEventListener('mousedown', startDrawing);
              canvas.addEventListener('mousemove', draw);
              canvas.addEventListener('mouseup', stopDrawing);
              canvas.addEventListener('wheel', handleZoom);
              
              document.querySelectorAll('.tool').forEach(tool => {
                tool.onclick = () => {
                  document.querySelector('.tool.active').classList.remove('active');
                  tool.classList.add('active');
                  currentTool = tool.dataset.tool;
                };
              });
            }
            
            function toCanvasPoint(clientX, clientY) {
              return {
                x: (clientX - viewportX) / zoom,
                y: (clientY - viewportY) / zoom
              };
            }
            
            function startDrawing(e) {
              isDrawing = true;
              const point = toCanvasPoint(e.clientX, e.clientY);
              startPoint = point;
              lastPoint = point;
            }
            
            function draw(e) {
              if (!isDrawing) return;
              
              const currentPoint = toCanvasPoint(e.clientX, e.clientY);
              
              if (currentTool === 'pen' || currentTool === 'eraser') {
                ws.send(JSON.stringify({
                  type: 'draw',
                  command_type: currentTool,
                  points: [lastPoint, currentPoint],
                  color: currentTool === 'eraser' ? '#ffffff' : document.getElementById('color').value,
                  size: document.getElementById('size').value
                }));
                
                lastPoint = currentPoint;
              } else {
                // Vista previa de formas
                redraw();
                ctx.save();
                ctx.translate(viewportX, viewportY);
                ctx.scale(zoom, zoom);
                ctx.beginPath();
                ctx.strokeStyle = document.getElementById('color').value;
                ctx.lineWidth = document.getElementById('size').value;
                
                switch(currentTool) {
                  case 'line':
                    ctx.moveTo(startPoint.x, startPoint.y);
                    ctx.lineTo(currentPoint.x, currentPoint.y);
                    break;
                    
                  case 'rectangle':
                    const width = currentPoint.x - startPoint.x;
                    const height = currentPoint.y - startPoint.y;
                    ctx.strokeRect(startPoint.x, startPoint.y, width, height);
                    break;
                    
                  case 'circle':
                    const radius = Math.sqrt(
                      Math.pow(currentPoint.x - startPoint.x, 2) +
                      Math.pow(currentPoint.y - startPoint.y, 2)
                    );
                    ctx.arc(startPoint.x, startPoint.y, radius, 0, Math.PI * 2);
                    break;
                }
                ctx.stroke();
                ctx.restore();
              }
            }
            
            function stopDrawing() {
              if (!isDrawing) return;
              isDrawing = false;
              
              if (['line', 'rectangle', 'circle'].includes(currentTool)) {
                const endPoint = lastPoint;
                ws.send(JSON.stringify({
                  type: 'draw',
                  command_type: 'shape',
                  shape_type: currentTool,
                  points: [startPoint, endPoint],
                  color: document.getElementById('color').value,
                  size: document.getElementById('size').value
                }));
              }
            }
            
            function handleZoom(e) {
              e.preventDefault();
              const delta = e.deltaY > 0 ? 0.9 : 1.1;
              const point = toCanvasPoint(e.clientX, e.clientY);
              
              zoom *= delta;
              viewportX = e.clientX - (point.x * zoom);
              viewportY = e.clientY - (point.y * zoom);
              
              redraw();
              
              ws.send(JSON.stringify({
                type: 'viewport',
                x: viewportX,
                y: viewportY,
                zoom: zoom
              }));
            }
            
            function executeCommand(command) {
              ctx.save();
              ctx.translate(viewportX, viewportY);
              ctx.scale(zoom, zoom);
              ctx.beginPath();
              ctx.strokeStyle = command.color;
              ctx.lineWidth = command.size;
              
              if (command.type === 'shape') {
                const [start, end] = command.points;
                
                switch(command.shape_type) {
                  case 'line':
                    ctx.moveTo(start.x, start.y);
                    ctx.lineTo(end.x, end.y);
                    break;
                    
                  case 'rectangle':
                    const width = end.x - start.x;
                    const height = end.y - start.y;
                    ctx.strokeRect(start.x, start.y, width, height);
                    break;
                    
                  case 'circle':
                    const radius = Math.sqrt(
                      Math.pow(end.x - start.x, 2) +
                      Math.pow(end.y - start.y, 2)
                    );
                    ctx.arc(start.x, start.y, radius, 0, Math.PI * 2);
                    break;
                }
              } else {
                ctx.moveTo(command.points[0].x, command.points[0].y);
                command.points.forEach(point => {
                  ctx.lineTo(point.x, point.y);
                });
              }
              
              ctx.stroke();
              ctx.restore();
            }
            
            function redraw() {
              ctx.clearRect(0, 0, canvas.width, canvas.height);
              canvas.commands?.forEach(executeCommand);
            }
            
            function updateUsers() {
              const usersDiv = document.getElementById('users');
              usersDiv.innerHTML = Object.entries(canvas.users)
                .map(([id, name]) => \`
                  <div class="user">
                    <div class="color-dot" style="background: \${id === userId ? '#000000' : '#666666'}"></div>
                    \${name} \${id === userId ? '(Tú)' : ''}
                  </div>
                \`).join('');
            }
            
            function joinCanvas() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('canvas-container').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/canvas?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                
                switch(data.type) {
                  case 'init':
                    canvas = data.canvas;
                    initCanvas();
                    redraw();
                    updateUsers();
                    break;
                    
                  case 'draw_update':
                    canvas.commands.push(data.command);
                    executeCommand(data.command);
                    break;
                    
                  case 'viewport_update':
                    // Actualizar indicadores de otros usuarios si es necesario
                    break;
                    
                  case 'error':
                    console.error(data.message);
                    break;
                }
              };
            }
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 