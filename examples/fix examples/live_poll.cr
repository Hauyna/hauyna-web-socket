require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de votación en vivo

class Poll
  include JSON::Serializable
  
  property question : String
  property options : Hash(String, Int32)
  property voters : Set(String)
  
  def initialize(@question : String, options : Array(String))
    @options = Hash(String, Int32).new(0)
    options.each { |opt| @options[opt] = 0 }
    @voters = Set(String).new
  end
  
  def vote(option : String, voter_id : String) : Bool
    return false if @voters.includes?(voter_id)
    return false unless @options.has_key?(option)
    
    @options[option] += 1
    @voters.add(voter_id)
    true
  end
end

# Crear una encuesta de ejemplo
poll = Poll.new(
  "¿Cuál es tu lenguaje de programación favorito?",
  ["Crystal", "Ruby", "Python", "JavaScript", "Go"]
)

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new

  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["voter_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if voter_id = params["voter_id"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.add_to_group(voter_id, "voters")
      socket.send({
        type: "poll_data",
        poll: poll
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if voter_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if data["type"]?.try(&.as_s) == "vote"
          if option = data["option"]?.try(&.as_s)
            if poll.vote(option, voter_id)
              Hauyna::WebSocket::Events.send_to_group("voters", {
                type: "poll_update",
                poll: poll
              }.to_json)
            else
              socket.send({
                type: "error",
                message: "Ya has votado o la opción no es válida"
              }.to_json)
            end
          end
        end
      rescue ex
        socket.send({
          type: "error",
          message: "Error al procesar el voto: #{ex.message}"
        }.to_json)
      end
    end
  }

  router.websocket("/poll", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Votación en Vivo</title>
          <style>
            .poll-container {
              max-width: 600px;
              margin: 20px auto;
              padding: 20px;
              background: #f5f5f5;
              border-radius: 8px;
            }
            .option {
              margin: 10px 0;
              padding: 10px;
              background: white;
              border-radius: 4px;
              cursor: pointer;
            }
            .option:hover {
              background: #e0e0e0;
            }
            .progress-bar {
              height: 20px;
              background: #ddd;
              border-radius: 10px;
              overflow: hidden;
              margin-top: 5px;
            }
            .progress {
              height: 100%;
              background: #4CAF50;
              width: 0%;
              transition: width 0.3s ease;
            }
            .votes {
              float: right;
              font-weight: bold;
            }
            #message {
              color: red;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="poll-container">
            <h2 id="question"></h2>
            <div id="options"></div>
            <div id="message"></div>
          </div>

          <script>
            const voterId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(`ws://localhost:8080/poll?voter_id=${voterId}`);
            const options = document.getElementById('options');
            const message = document.getElementById('message');
            let hasVoted = false;

            function updatePoll(poll) {
              document.getElementById('question').textContent = poll.question;
              
              const totalVotes = Object.values(poll.options).reduce((a, b) => a + b, 0);
              options.innerHTML = '';
              
              Object.entries(poll.options).forEach(([option, votes]) => {
                const percentage = totalVotes > 0 ? (votes / totalVotes * 100).toFixed(1) : 0;
                const div = document.createElement('div');
                div.className = 'option';
                div.innerHTML = \`
                  <div>
                    \${option}
                    <span class="votes">\${votes} votos (\${percentage}%)</span>
                  </div>
                  <div class="progress-bar">
                    <div class="progress" style="width: \${percentage}%"></div>
                  </div>
                \`;
                
                if (!hasVoted && !poll.voters.includes(voterId)) {
                  div.onclick = () => vote(option);
                }
                
                options.appendChild(div);
              });
              
              hasVoted = poll.voters.includes(voterId);
            }

            function vote(option) {
              ws.send(JSON.stringify({
                type: 'vote',
                option: option
              }));
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              if (data.type === 'error') {
                message.textContent = data.message;
                setTimeout(() => message.textContent = '', 3000);
              } else if (data.type === 'poll_data' || data.type === 'poll_update') {
                updatePoll(data.poll);
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