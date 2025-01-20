require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de juego tipo Pictionary

class Game
  include JSON::Serializable
  
  WORDS = ["gato", "perro", "casa", "árbol", "sol", "luna", "coche", "flor", "libro", "computadora"]
  
  property current_word : String
  property drawer_id : String?
  property players : Hash(String, Int32) # player_id => score
  property state : String # waiting, playing, round_end
  property time_left : Int32
  
  def initialize
    @current_word = ""
    @drawer_id = nil
    @players = {} of String => Int32
    @state = "waiting"
    @time_left = 60
  end
  
  def start_round(drawer : String)
    @drawer_id = drawer
    @current_word = WORDS.sample
    @state = "playing"
    @time_left = 60
  end
  
  def add_player(id : String)
    @players[id] = 0 unless @players[id]?
  end
  
  def score_guess(player_id : String)
    @players[player_id] += (@time_left > 30 ? 3 : 1) if @players[player_id]?
  end
end

game = Game.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["player_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if player_id = params["player_id"]?.try(&.as_s)
      game.add_player(player_id)
      Hauyna::WebSocket::ConnectionManager.add_to_group(player_id, "players")
      
      # Si no hay dibujante, asignar uno
      if game.drawer_id.nil? && game.state == "waiting"
        game.start_round(player_id)
      end
      
      Hauyna::WebSocket::Events.send_to_group("players", {
        type: "game_update",
        game: game
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "draw"
          if player_id == game.drawer_id
            Hauyna::WebSocket::Events.send_to_group("players", {
              type: "draw_update",
              lines: data["lines"]
            }.to_json)
          end
        when "guess"
          if player_id != game.drawer_id && game.state == "playing"
            guess = data["guess"].as_s.downcase
            if guess == game.current_word
              game.score_guess(player_id)
              game.state = "round_end"
              Hauyna::WebSocket::Events.send_to_group("players", {
                type: "correct_guess",
                winner: player_id,
                word: game.current_word,
                game: game
              }.to_json)
            end
          end
        when "next_round"
          if game.state == "round_end"
            # Rotar al siguiente dibujante
            current_players = game.players.keys
            current_index = current_players.index(game.drawer_id) || -1
            next_drawer = current_players[(current_index + 1) % current_players.size]
            game.start_round(next_drawer)
            Hauyna::WebSocket::Events.send_to_group("players", {
              type: "game_update",
              game: game
            }.to_json)
          end
        end
      rescue ex
        socket.send({
          type: "error",
          message: ex.message
        }.to_json)
      end
    end
  }

  # Iniciar el temporizador del juego
  spawn do
    loop do
      sleep 1.seconds
      next unless game.state == "playing" && game.time_left > 0
      
      game.time_left -= 1
      
      if game.time_left == 0
        game.state = "round_end"
        Hauyna::WebSocket::Events.send_to_group("players", {
          type: "time_up",
          word: game.current_word,
          game: game
        }.to_json)
      else
        begin
          Hauyna::WebSocket::Events.send_to_group("players", {
            type: "tick",
            time: game.time_left
          }.to_json)
        rescue ex
          puts "Error al enviar tick: #{ex.message}"
        end
      end
    end
  end

  router.websocket("/pictionary", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Pictionary</title>
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
            .sidebar {
              width: 200px;
            }
            .players {
              margin-top: 20px;
            }
            .word {
              font-size: 24px;
              font-weight: bold;
              margin-bottom: 10px;
            }
            #timer {
              font-size: 20px;
              color: #666;
            }
            #messages {
              height: 200px;
              overflow-y: auto;
              border: 1px solid #ccc;
              padding: 10px;
              margin-top: 10px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div>
              <canvas id="canvas" width="600" height="400"></canvas>
              <input type="text" id="guess" placeholder="Escribe tu respuesta...">
            </div>
            <div class="sidebar">
              <div id="word" class="word">Esperando...</div>
              <div id="timer"></div>
              <div id="players" class="players"></div>
              <div id="messages"></div>
            </div>
          </div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/pictionary?player_id=\${playerId}\`);
            const canvas = document.getElementById('canvas');
            const ctx = canvas.getContext('2d');
            const guess = document.getElementById('guess');
            let isDrawing = false;
            let isDrawer = false;
            
            ctx.lineJoin = 'round';
            ctx.lineCap = 'round';
            ctx.lineWidth = 2;

            canvas.addEventListener('mousedown', startDrawing);
            canvas.addEventListener('mousemove', draw);
            canvas.addEventListener('mouseup', stopDrawing);
            canvas.addEventListener('mouseout', stopDrawing);

            guess.addEventListener('keypress', (e) => {
              if (e.key === 'Enter' && !isDrawer) {
                ws.send(JSON.stringify({
                  type: 'guess',
                  guess: guess.value
                }));
                guess.value = '';
              }
            });

            function startDrawing(e) {
              if (!isDrawer) return;
              isDrawing = true;
              [lastX, lastY] = [e.offsetX, e.offsetY];
            }

            function draw(e) {
              if (!isDrawing || !isDrawer) return;
              
              ctx.beginPath();
              ctx.moveTo(lastX, lastY);
              ctx.lineTo(e.offsetX, e.offsetY);
              ctx.stroke();
              
              ws.send(JSON.stringify({
                type: 'draw',
                lines: {
                  fromX: lastX,
                  fromY: lastY,
                  toX: e.offsetX,
                  toY: e.offsetY
                }
              }));
              
              [lastX, lastY] = [e.offsetX, e.offsetY];
            }

            function stopDrawing() {
              isDrawing = false;
            }

            function addMessage(text) {
              const div = document.createElement('div');
              div.textContent = text;
              messages.appendChild(div);
              messages.scrollTop = messages.scrollHeight;
            }

            function updatePlayers(game) {
              const playersList = document.getElementById('players');
              playersList.innerHTML = Object.entries(game.players)
                .map(([id, score]) => \`
                  <div>\${id === playerId ? 'Tú' : id} (\${score} puntos)
                    \${id === game.drawer_id ? ' - Dibujante' : ''}
                  </div>
                \`).join('');
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'game_update':
                  isDrawer = data.game.drawer_id === playerId;
                  guess.style.display = isDrawer ? 'none' : 'block';
                  document.getElementById('word').textContent = isDrawer ? 
                    \`Dibuja: \${data.game.current_word}\` : 
                    'Adivina la palabra';
                  updatePlayers(data.game);
                  break;
                  
                case 'draw_update':
                  if (!isDrawer) {
                    const lines = data.lines;
                    ctx.beginPath();
                    ctx.moveTo(lines.fromX, lines.fromY);
                    ctx.lineTo(lines.toX, lines.toY);
                    ctx.stroke();
                  }
                  break;
                  
                case 'correct_guess':
                  ctx.clearRect(0, 0, canvas.width, canvas.height);
                  addMessage(\`¡\${data.winner} adivinó la palabra "\${data.word}"!\`);
                  updatePlayers(data.game);
                  setTimeout(() => {
                    ws.send(JSON.stringify({ type: 'next_round' }));
                  }, 3000);
                  break;
                  
                case 'time_up':
                  addMessage(\`¡Se acabó el tiempo! La palabra era "\${data.word}"\`);
                  updatePlayers(data.game);
                  setTimeout(() => {
                    ws.send(JSON.stringify({ type: 'next_round' }));
                  }, 3000);
                  break;
                  
                case 'tick':
                  document.getElementById('timer').textContent = \`Tiempo: \${data.time}s\`;
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