require "../src/hauyna-web-socket"
require "http/server"

# Juego de trivia multijugador

class Question
  include JSON::Serializable

  property text : String
  property options : Array(String)
  property correct : Int32
  property time_limit : Int32

  def initialize(@text : String, @options : Array(String), @correct : Int32, @time_limit : Int32 = 30)
  end
end

class Player
  include JSON::Serializable

  property id : String
  property name : String
  property score : Int32
  property current_answer : Int32?

  def initialize(@id : String, @name : String)
    @score = 0
    @current_answer = nil
  end

  def answer(question_index : Int32, answer : Int32)
    @current_answer = answer
  end

  def reset_answer
    @current_answer = nil
  end
end

class Game
  include JSON::Serializable

  property questions : Array(Question)
  property players : Hash(String, Player)
  property current_question : Int32
  property state : String # waiting, playing, showing_answer, finished
  property time_left : Int32

  def initialize
    @questions = [
      Question.new(
        "¿Cuál es el lenguaje de programación más antiguo aún en uso?",
        ["FORTRAN", "COBOL", "LISP", "BASIC"],
        0
      ),
      Question.new(
        "¿En qué año se creó el lenguaje Crystal?",
        ["2010", "2011", "2012", "2014"],
        2
      ),
      Question.new(
        "¿Quién creó el lenguaje Ruby?",
        ["Yukihiro Matsumoto", "Guido van Rossum", "Brendan Eich", "James Gosling"],
        0
      ),
    ]
    @players = {} of String => Player
    @current_question = 0
    @state = "waiting"
    @time_left = 30
  end

  def add_player(id : String, name : String)
    @players[id] = Player.new(id, name)
  end

  def start
    return false if @players.empty?
    @state = "playing"
    @time_left = current_question_obj.time_limit
    true
  end

  def current_question_obj : Question
    @questions[@current_question]
  end

  def answer(player_id : String, answer : Int32)
    return false unless @state == "playing"
    return false unless (0...current_question_obj.options.size).includes?(answer)

    if player = @players[player_id]?
      player.answer(@current_question, answer)
      true
    else
      false
    end
  end

  def show_answer
    @state = "showing_answer"

    @players.each_value do |player|
      if player.current_answer == current_question_obj.correct
        player.score += 100
      end
    end
  end

  def next_question
    @current_question += 1

    if @current_question >= @questions.size
      @state = "finished"
    else
      @state = "playing"
      @time_left = current_question_obj.time_limit
      @players.each_value(&.reset_answer)
    end
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
        game.add_player(player_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(player_id, "players")

        # Iniciar juego si hay suficientes jugadores
        if game.players.size >= 2 && game.state == "waiting"
          game.start
        end

        Hauyna::WebSocket::Events.send_to_group("players", {
          type: "game_update",
          game: game,
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if player_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "answer"
          if answer = data["answer"]?.try(&.as_i)
            if game.answer(player_id, answer)
              Hauyna::WebSocket::Events.send_to_group("players", {
                type: "game_update",
                game: game,
              }.to_json)
            end
          end
        end
      rescue ex
        socket.send({
          type:    "error",
          message: ex.message,
        }.to_json)
      end
    end
  }

  # Temporizador del juego
  spawn do
    loop do
      sleep 1.seconds
      if game.state == "playing" && game.time_left > 0
        game.time_left -= 1

        if game.time_left == 0
          game.show_answer

          Hauyna::WebSocket::Events.send_to_group("players", {
            type: "game_update",
            game: game,
          }.to_json)

          sleep 5.seconds

          game.next_question
          Hauyna::WebSocket::Events.send_to_group("players", {
            type: "game_update",
            game: game,
          }.to_json)
        else
          Hauyna::WebSocket::Events.send_to_group("players", {
            type: "time_update",
            time: game.time_left,
          }.to_json)
        end
      end
    end
  end

  router.websocket("/trivia", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Trivia Multijugador</title>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .question {
              font-size: 24px;
              margin-bottom: 20px;
            }
            .options {
              display: grid;
              grid-template-columns: repeat(2, 1fr);
              gap: 10px;
            }
            .option {
              padding: 15px;
              border: 1px solid #ccc;
              border-radius: 4px;
              cursor: pointer;
              text-align: center;
            }
            .option:hover {
              background: #f5f5f5;
            }
            .option.selected {
              background: #e3f2fd;
              border-color: #2196F3;
            }
            .option.correct {
              background: #c8e6c9;
              border-color: #4CAF50;
            }
            .option.incorrect {
              background: #ffcdd2;
              border-color: #f44336;
            }
            .players {
              margin-top: 20px;
            }
            .player {
              display: flex;
              justify-content: space-between;
              padding: 10px;
              border-bottom: 1px solid #eee;
            }
            .timer {
              font-size: 24px;
              text-align: center;
              margin: 20px 0;
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
              <div class="timer" id="timer"></div>
              <div class="question" id="question"></div>
              <div class="options" id="options"></div>
              <div class="players" id="players"></div>
            </div>
          </div>

          <script>
            const playerId = Math.random().toString(36).substr(2, 9);
            let ws;
            let game;
            let selectedAnswer;
            
            function joinGame() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('game').style.display = 'block';
              
              ws = new WebSocket(
                `ws://localhost:8080/trivia?player_id=${playerId}&name=${name}`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function updateUI() {
              if (!game) return;
              
              const question = game.questions[game.current_question];
              document.getElementById('question').textContent = question.text;
              
              const options = document.getElementById('options');
              options.innerHTML = question.options.map((option, index) => {
                let className = 'option';
                if (index === selectedAnswer) {
                  className += ' selected';
                }
                if (game.state === 'showing_answer') {
                  if (index === question.correct) {
                    className += ' correct';
                  } else if (index === selectedAnswer) {
                    className += ' incorrect';
                  }
                }
                return `
                  <div class="${className}"
                       onclick="selectAnswer(${index})"
                       ${game.state !== 'playing' ? 'style="pointer-events: none"' : ''}>
                    ${option}
                  </div>
                `;
              }).join('');
              
              const players = document.getElementById('players');
              players.innerHTML = Object.values(game.players)
                .sort((a, b) => b.score - a.score)
                .map(player => `
                  <div class="player">
                    <span>${player.name}</span>
                    <span>${player.score} puntos</span>
                  </div>
                `).join('');
            }
            
            function selectAnswer(index) {
              if (game.state === 'playing') {
                selectedAnswer = index;
                ws.send(JSON.stringify({
                  type: 'answer',
                  answer: index
                }));
                updateUI();
              }
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'game_update':
                  game = data.game;
                  updateUI();
                  break;
                  
                case 'time_update':
                  document.getElementById('timer').textContent = 
                    `Tiempo: ${data.time}s`;
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
