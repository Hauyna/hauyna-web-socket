require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de juego de cartas simple (UNO simplificado)

class Card
  include JSON::Serializable
  
  property color : String
  property value : String
  
  def initialize(@color : String, @value : String)
  end
  
  def matches?(other : Card) : Bool
    color == other.color || value == other.value
  end
end

class Game
  include JSON::Serializable
  
  COLORS = ["red", "blue", "green", "yellow"]
  VALUES = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  
  property deck : Array(Card)
  property discard_pile : Array(Card)
  property players : Hash(String, Array(Card))
  property current_player : String?
  property direction : Int32 # 1 o -1
  property status : String
  
  def initialize
    @deck = [] of Card
    @discard_pile = [] of Card
    @players = {} of String => Array(Card)
    @current_player = nil
    @direction = 1
    @status = "waiting"
    
    # Crear mazo
    COLORS.each do |color|
      VALUES.each do |value|
        2.times { @deck << Card.new(color, value) }
      end
    end
    
    shuffle_deck
  end
  
  def shuffle_deck
    @deck.shuffle!
  end
  
  def deal_cards(player_id : String)
    @players[player_id] = [] of Card
    7.times { @players[player_id] << @deck.pop }
  end
  
  def start_game
    return false if @players.size < 2
    @status = "playing"
    @current_player = @players.keys.first
    @discard_pile << @deck.pop
    true
  end
  
  def play_card(player_id : String, card_index : Int32) : Bool
    return false unless can_play?(player_id, card_index)
    
    player_cards = @players[player_id]
    card = player_cards[card_index]
    
    if card.matches?(@discard_pile.last)
      @discard_pile << player_cards.delete_at(card_index)
      next_turn
      true
    else
      false
    end
  end
  
  def draw_card(player_id : String) : Bool
    return false unless player_id == @current_player
    
    if @deck.empty?
      top_card = @discard_pile.pop
      @deck = @discard_pile.shuffle!
      @discard_pile = [top_card]
    end
    
    @players[player_id] << @deck.pop
    next_turn
    true
  end
  
  private def next_turn
    player_order = @players.keys
    current_index = player_order.index(@current_player.not_nil!)
    next_index = (current_index.not_nil! + @direction) % player_order.size
    @current_player = player_order[next_index]
  end
  
  private def can_play?(player_id : String, card_index : Int32) : Bool
    return false unless player_id == @current_player
    return false unless (0...@players[player_id].size).includes?(card_index)
    true
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
      if game.status == "waiting"
        game.deal_cards(player_id)
        Hauyna::WebSocket::ConnectionManager.add_to_group(player_id, "players")
        
        # Iniciar juego si hay suficientes jugadores
        if game.players.size >= 2
          game.start_game
        end
      end
      
      socket.send({
        type: "game_state",
        game: game,
        your_cards: game.players[player_id]?
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["action"]?.try(&.as_s)
        when "play"
          if card_index = data["card_index"]?.try(&.as_i)
            if game.play_card(player_id, card_index)
              game.players.each_key do |pid|
                Hauyna::WebSocket::Events.send_to_group(pid, {
                  type: "game_state",
                  game: game,
                  your_cards: game.players[pid]
                }.to_json)
              end
            else
              socket.send({
                type: "error",
                message: "Jugada inválida"
              }.to_json)
            end
          end
        when "draw"
          if game.draw_card(player_id)
            game.players.each_key do |pid|
              Hauyna::WebSocket::Events.send_to_group(pid, {
                type: "game_state",
                game: game,
                your_cards: game.players[pid]
              }.to_json)
            end
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

  router.websocket("/card-game", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Juego de Cartas</title>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .game-area {
              display: flex;
              flex-direction: column;
              gap: 20px;
              align-items: center;
            }
            .cards {
              display: flex;
              gap: 10px;
              flex-wrap: wrap;
              justify-content: center;
            }
            .card {
              width: 80px;
              height: 120px;
              border: 2px solid #333;
              border-radius: 8px;
              display: flex;
              align-items: center;
              justify-content: center;
              font-size: 24px;
              cursor: pointer;
              user-select: none;
            }
            .card:hover {
              transform: translateY(-5px);
            }
            .red { background: #ffcdd2; }
            .blue { background: #bbdefb; }
            .green { background: #c8e6c9; }
            .yellow { background: #fff9c4; }
            .discard-pile {
              border: 2px dashed #666;
              padding: 20px;
              margin: 20px 0;
            }
            .status {
              font-size: 20px;
              margin: 10px 0;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="game-area">
              <div id="status" class="status">Esperando jugadores...</div>
              <div id="error"></div>
              <div id="discard-pile" class="discard-pile">
                <div id="top-card"></div>
              </div>
              <button onclick="drawCard()">Robar Carta</button>
              <div id="your-cards" class="cards"></div>
            </div>
          </div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/card-game?player_id=\${playerId}\`);
            
            function createCard(card, index) {
              const div = document.createElement('div');
              div.className = \`card \${card.color}\`;
              div.textContent = card.value;
              div.onclick = () => playCard(index);
              return div;
            }

            function updateGame(gameState) {
              const status = document.getElementById('status');
              const yourCards = document.getElementById('your-cards');
              const topCard = document.getElementById('top-card');
              const error = document.getElementById('error');
              
              // Actualizar estado
              status.textContent = gameState.game.current_player === playerId ? 
                'Tu turno' : \`Turno de \${gameState.game.current_player}\`;
              
              // Actualizar carta superior
              const lastCard = gameState.game.discard_pile[gameState.game.discard_pile.length - 1];
              if (lastCard) {
                topCard.innerHTML = '';
                topCard.appendChild(createCard(lastCard));
              }
              
              // Actualizar tus cartas
              yourCards.innerHTML = '';
              if (gameState.your_cards) {
                gameState.your_cards.forEach((card, index) => {
                  yourCards.appendChild(createCard(card, index));
                });
              }
            }

            function playCard(index) {
              ws.send(JSON.stringify({
                action: 'play',
                card_index: index
              }));
            }

            function drawCard() {
              ws.send(JSON.stringify({
                action: 'draw'
              }));
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              if (data.type === 'game_state') {
                updateGame(data);
              } else if (data.type === 'error') {
                const error = document.getElementById('error');
                error.textContent = data.message;
                setTimeout(() => error.textContent = '', 3000);
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