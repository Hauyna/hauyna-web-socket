require "../src/hauyna-web-socket"
require "http/server"

# Juego de memoria multijugador

class Card
  include JSON::Serializable

  property id : Int32
  property value : String
  property revealed : Bool
  property matched : Bool

  def initialize(@id : Int32, @value : String)
    @revealed = false
    @matched = false
  end
end

class Player
  include JSON::Serializable

  property id : String
  property name : String
  property score : Int32
  property is_turn : Bool

  def initialize(@id : String, @name : String)
    @score = 0
    @is_turn = false
  end
end

class Game
  include JSON::Serializable

  EMOJIS = ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯"]

  property cards : Array(Card)
  property players : Hash(String, Player)
  property state : String # waiting, playing, finished
  property revealed_cards : Array(Card)
  property current_player : String?

  def initialize
    @cards = [] of Card
    @players = {} of String => Player
    @state = "waiting"
    @revealed_cards = [] of Card
    @current_player = nil

    # Crear cartas
    emojis = EMOJIS.first(6)
    id = 0
    emojis.each do |emoji|
      2.times do
        @cards << Card.new(id, emoji)
        id += 1
      end
    end
    @cards.shuffle!
  end

  def add_player(id : String, name : String)
    @players[id] = Player.new(id, name)
    if @players.size == 2
      start_game
    end
  end

  def start_game
    @state = "playing"
    @current_player = @players.keys.first
    @players[@current_player.not_nil!].is_turn = true
  end

  def reveal_card(card_id : Int32)
    return false unless @state == "playing"
    return false if @revealed_cards.size >= 2

    if card = @cards.find { |c| c.id == card_id }
      return false if card.revealed || card.matched

      card.revealed = true
      @revealed_cards << card

      if @revealed_cards.size == 2
        check_match
      end

      true
    else
      false
    end
  end

  private def check_match
    if @revealed_cards[0].value == @revealed_cards[1].value
      @revealed_cards.each(&.matched = true)
      if current = @current_player
        @players[current].score += 1
      end

      if @cards.all?(&.matched)
        @state = "finished"
      end
    else
      next_turn
    end
  end

  def hide_revealed
    @revealed_cards.each(&.revealed = false)
    @revealed_cards.clear
  end

  private def next_turn
    if current = @current_player
      @players[current].is_turn = false
      next_player = @players.keys.find { |id| id != current }
      if next_player
        @current_player = next_player
        @players[next_player].is_turn = true
      end
    end
  end
end

game = Game.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new(
    extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      params["player_id"]?.try(&.as_s)
    },

    on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
      if player_id = params["player_id"]?.try(&.as_s)
        name = params["name"]?.try(&.as_s) || "Jugador #{player_id}"
        game.add_player(player_id, name)

        socket.send(JSON.build { |json|
          json.object do
            json.field "type", "game_update"
            json.field "game", game
          end
        })
      end
    },

    on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
      if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        if data["type"]?.try(&.as_s) == "reveal" &&
           (card_id = data["card_id"]?.try(&.as_i))
          if game.reveal_card(card_id)
            socket.send(JSON.build { |json|
              json.object do
                json.field "type", "game_update"
                json.field "game", game
              end
            })

            if game.revealed_cards.size == 2
              sleep 1.seconds
              game.hide_revealed
              socket.send(JSON.build { |json|
                json.object do
                  json.field "type", "game_update"
                  json.field "game", game
                end
              })
            end
          end
        end
      end
    }
  )

  router.websocket("/memory", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Juego de Memoria</title>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .board {
              display: grid;
              grid-template-columns: repeat(4, 1fr);
              gap: 10px;
              margin: 20px 0;
            }
            .card {
              aspect-ratio: 1;
              background: #2196F3;
              border-radius: 4px;
              cursor: pointer;
              display: flex;
              align-items: center;
              justify-content: center;
              font-size: 40px;
              transition: all 0.3s;
            }
            .card.revealed {
              background: white;
              transform: rotateY(180deg);
            }
            .card.matched {
              background: #4CAF50;
              cursor: default;
            }
            .players {
              display: flex;
              justify-content: space-around;
              margin: 20px 0;
            }
            .player {
              text-align: center;
              padding: 10px;
              border-radius: 4px;
            }
            .player.current {
              background: #e3f2fd;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Unirse al Juego</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinGame()">Jugar</button>
            </div>
            
            <div id="game" style="display: none;">
              <div class="players" id="players"></div>
              <div class="board" id="board"></div>
            </div>
          </div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            let ws;
            let game;
            
            function joinGame() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('game').style.display = 'block';
              
              ws = new WebSocket(
                `ws://localhost:8080/memory?player_id=${playerId}&name=${name}`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function revealCard(cardId) {
              if (!game || game.state !== 'playing') return;
              if (!game.players[playerId].is_turn) return;
              if (game.revealed_cards.length >= 2) return;
              
              ws.send(JSON.stringify({
                type: 'reveal',
                card_id: cardId
              }));
            }
            
            function updateBoard() {
              const board = document.getElementById('board');
              board.innerHTML = game.cards.map(card => `
                <div class="card ${card.revealed ? 'revealed' : ''} ${card.matched ? 'matched' : ''}"
                     onclick="revealCard(${card.id})">
                  ${card.revealed || card.matched ? card.value : ''}
                </div>
              `).join('');
              
              const players = document.getElementById('players');
              players.innerHTML = Object.values(game.players).map(player => `
                <div class="player ${player.is_turn ? 'current' : ''}">
                  <div>${player.name}</div>
                  <div>${player.score} pares</div>
                  ${player.is_turn ? '(Tu turno)' : ''}
                </div>
              `).join('');
              
              if (game.state === 'finished') {
                const winner = Object.values(game.players)
                  .reduce((a, b) => a.score > b.score ? a : b);
                alert(`¡Juego terminado! Ganador: ${winner.name}`);
              }
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'game_update':
                  game = data.game;
                  updateBoard();
                  break;
                  
                case 'error':
                  console.error(data.message);
                  break;
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
