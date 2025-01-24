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
  property player_names : Hash(String, String)
  property current_player : String?
  property direction : Int32 # 1 o -1
  property status : String
  
  MIN_PLAYERS = 2
  MAX_PLAYERS = 4 # Agregar límite máximo de jugadores
  
  def initialize
    @deck = [] of Card
    @discard_pile = [] of Card
    @players = {} of String => Array(Card)
    @player_names = {} of String => String
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
  
  def add_player(player_id : String, name : String) : Bool
    return false if @status != "waiting" || @players.size >= MAX_PLAYERS
    @player_names[player_id] = name
    deal_cards(player_id)
    
    # Iniciar el juego automáticamente si alcanzamos el mínimo de jugadores
    if @players.size >= MIN_PLAYERS
      start_game
    end
    true
  end
  
  def start_game : Bool
    return false if @players.size < MIN_PLAYERS
    return false if @status != "waiting"
    
    @status = "playing"
    @current_player = @players.keys.first
    @discard_pile << @deck.pop
    
    # Asegurarse de que la primera carta no sea especial
    while @discard_pile.last.value.to_i? == nil
      @deck.unshift(@discard_pile.pop)
      @discard_pile << @deck.pop
    end
    
    puts "Juego iniciado con #{@players.size} jugadores. Primer jugador: #{@current_player}"
    true
  end
  
  def play_card(player_id : String, card_index : Int32) : Bool
    return false unless can_play?(player_id, card_index)
    
    player_cards = @players[player_id]
    return false if card_index >= player_cards.size
    
    card = player_cards[card_index]
    top_card = @discard_pile.last
    
    if card.matches?(top_card)
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
    return false unless @players[player_id]?
    return false unless (0...@players[player_id].size).includes?(card_index)
    true
  end
  
  def player_count : Int32
    @players.size
  end
  
  def players_needed : Int32
    [MIN_PLAYERS - @players.size, 0].max
  end
  
  def game_state_for_player(player_id : String) : Hash(String, JSON::Any)
    state = {
      status: @status,
      current_player: @current_player || "",  # Evitar nil
      players: @players.keys,
      player_names: @player_names,
      discard_pile: @discard_pile.map { |card| {
        color: card.color,
        value: card.value
      }},
      direction: @direction
    }
    
    puts "Estado actual: #{state.to_json}"
    
    {
      "type" => JSON::Any.new("game_state"),
      "game" => JSON.parse(state.to_json),
      "your_cards" => @players[player_id]? ? JSON.parse(@players[player_id].to_json) : JSON::Any.new(nil),
      "can_play" => JSON::Any.new(@status == "playing" && @current_player == player_id)
    }
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
      if name = params["name"]?.try(&.as_s)
        puts "Nuevo jugador conectado: #{name} (#{player_id})"
        
        if game.status == "waiting"
          if game.add_player(player_id, name)
            Hauyna::WebSocket::ConnectionManager.add_to_group(player_id, "players")
            
            # Notificar a todos los jugadores del nuevo estado
            game.players.each_key do |pid|
              puts "Enviando estado actualizado a #{pid}"
              Hauyna::WebSocket::Events.send_to_group(pid, game.game_state_for_player(pid).to_json)
            end
          else
            socket.send({
              type: "error",
              message: "El juego está lleno"
            }.to_json)
          end
        else
          # Si el juego ya comenzó, verificar si es un jugador reconectándose
          if game.players.has_key?(player_id)
            Hauyna::WebSocket::ConnectionManager.add_to_group(player_id, "players")
            socket.send(game.game_state_for_player(player_id).to_json)
          else
            socket.send({
              type: "error",
              message: "El juego ya comenzó"
            }.to_json)
          end
        end
      end
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
              # Notificar a todos los jugadores del nuevo estado
              game.players.each_key do |pid|
                Hauyna::WebSocket::Events.send_to_group(pid, game.game_state_for_player(pid).to_json)
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
            # Notificar a todos los jugadores del nuevo estado
            game.players.each_key do |pid|
              Hauyna::WebSocket::Events.send_to_group(pid, game.game_state_for_player(pid).to_json)
            end
          else
            socket.send({
              type: "error",
              message: "No puedes robar carta en este momento"
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
            button:disabled {
              opacity: 0.5;
              cursor: not-allowed;
            }
            .status {
              font-size: 20px;
              margin: 10px 0;
              padding: 10px;
              background: #f5f5f5;
              border-radius: 5px;
            }
            #join {
              max-width: 400px;
              margin: 40px auto;
              padding: 20px;
              background: #f5f5f5;
              border-radius: 10px;
              text-align: center;
            }
            #join input {
              padding: 10px;
              margin: 10px;
              width: 200px;
            }
            #join button {
              padding: 10px 20px;
              background: #4CAF50;
              color: white;
              border: none;
              border-radius: 5px;
              cursor: pointer;
            }
            #join button:hover {
              background: #45a049;
            }
            .player-list {
              background: #f5f5f5;
              padding: 15px;
              border-radius: 5px;
              margin: 10px 0;
            }
            .player-list ul {
              list-style: none;
              padding: 0;
              margin: 10px 0;
            }
            .player-list li {
              padding: 5px 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>UNO Simplificado</h2>
              <p>Se necesitan 2 jugadores para comenzar</p>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinGame()">Unirse al Juego</button>
            </div>
            
            <div id="game" style="display: none;">
              <div class="game-area">
                <div id="status" class="status">Esperando jugadores...</div>
                <div id="error"></div>
                <div id="discard-pile" class="discard-pile">
                  <div id="top-card"></div>
                </div>
                <button id="drawButton" onclick="drawCard()" disabled>Robar Carta</button>
                <div id="your-cards" class="cards"></div>
              </div>
            </div>
          </div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            let ws;
            let gameState;

            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              if (data.type === 'game_state') {
                updateGame(data);
              } else if (data.type === 'error') {
                showError(data.message);
              }
            }
            
            function joinGame() {
              const name = document.getElementById('name').value.trim();
              if (!name) {
                showError('Por favor ingresa tu nombre');
                return;
              }
              
              ws = new WebSocket(\`ws://localhost:8080/card-game?player_id=\${playerId}&name=\${name}\`);
              
              ws.onopen = () => {
                document.getElementById('join').style.display = 'none';
                document.getElementById('game').style.display = 'block';
              };
              
              ws.onmessage = handleMessage;
              
              ws.onerror = () => {
                showError('Error de conexión');
              };
              
              ws.onclose = () => {
                showError('Conexión cerrada');
                document.getElementById('join').style.display = 'block';
                document.getElementById('game').style.display = 'none';
              };
            }

            function updateGame(data) {
              gameState = data;
              const status = document.getElementById('status');
              const yourCards = document.getElementById('your-cards');
              const topCard = document.getElementById('top-card');
              const drawButton = document.getElementById('drawButton');
              
              // Asegurarnos de parsear el estado del juego correctamente
              let game;
              try {
                game = typeof data.game === 'string' ? JSON.parse(data.game) : data.game;
                console.log('Game state parsed:', game); // Debug
              } catch (e) {
                console.error('Error parsing game state:', e);
                return;
              }
              
              // Actualizar estado del juego
              if (game.status === 'waiting') {
                const playerCount = game.players.length;
                status.textContent = \`Esperando jugadores... (${playerCount}/2)\`;
                drawButton.disabled = true;
              } else if (game.status === 'playing') {
                console.log('Game is playing, can_play:', data.can_play); // Debug
                if (data.can_play) {
                  status.textContent = 'Tu turno';
                  drawButton.disabled = false;
                } else {
                  const currentPlayerName = game.player_names[game.current_player] || 'Otro jugador';
                  status.textContent = \`Turno de \${currentPlayerName}\`;
                  drawButton.disabled = true;
                }
                
                // Mostrar la carta superior
                const lastCard = game.discard_pile[game.discard_pile.length - 1];
                if (lastCard) {
                  topCard.innerHTML = '';
                  topCard.appendChild(createCard(lastCard));
                }
              }
              
              // Mostrar lista de jugadores
              const playerList = document.createElement('div');
              playerList.className = 'player-list';
              playerList.innerHTML = \`
                <h3>Jugadores (${game.players.length}/2):</h3>
                <ul>
                  \${Object.entries(game.player_names).map(([id, name]) => \`
                    <li>
                      \${name}
                      \${id === playerId ? ' (Tú)' : ''}
                      \${id === game.current_player ? ' 🎮' : ''}
                      \${game.status === 'playing' ? (id === game.current_player ? ' - En turno' : '') : ''}
                    </li>
                  \`).join('')}
                </ul>
              \`;
              
              // Actualizar cartas del jugador
              let cards;
              try {
                cards = typeof data.your_cards === 'string' ? JSON.parse(data.your_cards) : data.your_cards;
                if (cards === 'null') cards = null;
                console.log('Player cards:', cards); // Debug
              } catch (e) {
                console.error('Error parsing cards:', e);
                return;
              }
              
              yourCards.innerHTML = '';
              if (cards) {
                cards.forEach((card, index) => {
                  const cardElement = createCard(card, index);
                  if (data.can_play) {
                    cardElement.style.cursor = 'pointer';
                    cardElement.onclick = () => playCard(index);
                  } else {
                    cardElement.style.cursor = 'not-allowed';
                    cardElement.onclick = null;
                  }
                  yourCards.appendChild(cardElement);
                });
              }
            }

            function createCard(card, index) {
              const div = document.createElement('div');
              div.className = \`card \${card.color}\`;
              div.textContent = card.value;
              if (gameState && gameState.can_play) {
                div.onclick = () => playCard(index);
                div.style.cursor = 'pointer';
              } else {
                div.style.cursor = 'not-allowed';
              }
              return div;
            }

            function playCard(index) {
              if (!gameState || !gameState.can_play) {
                showError('No es tu turno');
                return;
              }
              
              ws.send(JSON.stringify({
                action: 'play',
                card_index: index
              }));
            }

            function drawCard() {
              if (!gameState || !gameState.can_play) {
                showError('No es tu turno');
                return;
              }
              
              ws.send(JSON.stringify({
                action: 'draw'
              }));
            }

            function showError(message) {
              const error = document.getElementById('error');
              error.textContent = message;
              setTimeout(() => error.textContent = '', 3000);
            }
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 