require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de juego Tic-Tac-Toe multiplayer usando Hauyna WebSocket

class TicTacToeGame
  include JSON::Serializable

  property board : Array(String)
  property current_player : String
  property players : Hash(String, String) # player_id => X/O
  property status : String

  def initialize
    @board = Array.new(9, "")
    @current_player = "X"
    @players = {} of String => String
    @status = "waiting" # waiting, playing, finished
  end

  def make_move(position : Int32, player : String) : Bool
    return false if position < 0 || position > 8
    return false if @board[position] != ""
    return false if @players[player]? != @current_player

    @board[position] = @current_player
    @current_player = @current_player == "X" ? "O" : "X"
    true
  end

  def check_winner : String?
    # Líneas horizontales
    3.times do |i|
      if @board[i*3] != "" && @board[i*3] == @board[i*3 + 1] && @board[i*3] == @board[i*3 + 2]
        return @board[i*3]
      end
    end

    # Líneas verticales
    3.times do |i|
      if @board[i] != "" && @board[i] == @board[i + 3] && @board[i] == @board[i + 6]
        return @board[i]
      end
    end

    # Diagonales
    if @board[0] != "" && @board[0] == @board[4] && @board[0] == @board[8]
      return @board[0]
    end

    if @board[2] != "" && @board[2] == @board[4] && @board[2] == @board[6]
      return @board[2]
    end

    # Empate
    return "draw" if @board.all? { |cell| cell != "" }

    nil
  end
end

game = TicTacToeGame.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  handler = Hauyna::WebSocket::Handler.new(
    extract_identifier: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      params["player_id"]?.try(&.as_s)
    },

    on_open: ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
      if player_id = params["player_id"]?.try(&.as_s)
        if game.players.size < 2
          mark = game.players.empty? ? "X" : "O"
          game.players[player_id] = mark
          game.status = "playing" if game.players.size == 2
          Hauyna::WebSocket::Events.broadcast(game.to_json)
        else
          socket.send({error: "Juego lleno"}.to_json)
          socket.close
        end
      end
    },

    on_message: ->(socket : HTTP::WebSocket, message : String) {
      if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        begin
          data = JSON.parse(message)
          position = data["position"].as_i

          if game.make_move(position, player_id)
            if winner = game.check_winner
              game.status = "finished"
              winner_message = winner == "draw" ? "Empate!" : "Ganador: #{winner}"
              response = {
                game:   game,
                winner: winner_message,
              }
              Hauyna::WebSocket::Events.broadcast(response.to_json)
            else
              Hauyna::WebSocket::Events.broadcast(game.to_json)
            end
          end
        rescue ex
          socket.send({error: "Movimiento inválido - #{ex.message}"}.to_json)
        end
      end
    },

    on_close: ->(socket : HTTP::WebSocket) {
      if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        game.players.delete(player_id)
        game.status = "waiting"
        game.board = Array.new(9, "")
        game.current_player = "X"
        Hauyna::WebSocket::Events.broadcast(game.to_json)
      end
    }
  )

  router.websocket("/game", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Tic Tac Toe</title>
          <style>
            .board {
              display: grid;
              grid-template-columns: repeat(3, 100px);
              gap: 5px;
              margin: 20px auto;
              width: 310px;
            }
            .cell {
              height: 100px;
              background: #f0f0f0;
              border: none;
              font-size: 40px;
              cursor: pointer;
            }
            .cell:hover {
              background: #e0e0e0;
            }
            #status {
              text-align: center;
              margin: 20px;
              font-size: 24px;
            }
          </style>
        </head>
        <body>
          <div id="status">Conectando...</div>
          <div class="board" id="board"></div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(`ws://localhost:8080/game?player_id=${playerId}`);
            const board = document.getElementById('board');
            const status = document.getElementById('status');
            let myMark = '';

            // Crear el tablero
            for (let i = 0; i < 9; i++) {
              const cell = document.createElement('button');
              cell.className = 'cell';
              cell.dataset.position = i;
              cell.onclick = () => makeMove(i);
              board.appendChild(cell);
            }

            function updateBoard(gameData) {
              const cells = document.querySelectorAll('.cell');
              gameData.board.forEach((mark, i) => {
                cells[i].textContent = mark;
              });
            }

            function makeMove(position) {
              ws.send(JSON.stringify({ position }));
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              if (data.error) {
                status.textContent = data.error;
                return;
              }

              if (data.winner) {
                status.textContent = data.winner;
                updateBoard(data.game);
                return;
              }

              const game = data.players ? data : data.game;
              
              // Actualizar el estado del juego
              if (game.status === 'waiting') {
                status.textContent = 'Esperando otro jugador...';
              } else if (game.status === 'playing') {
                if (!myMark) {
                  myMark = game.players[playerId];
                }
                status.textContent = `Tu marca: ${myMark} | Turno: ${game.current_player}`;
              }

              updateBoard(game);
            };
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080)
