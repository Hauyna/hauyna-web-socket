require "../src/hauyna-web-socket"
require "http/server"

# Sistema de votación en tiempo real con gráficos

class Poll
  include JSON::Serializable
  
  property title : String
  property options : Hash(String, Int32)
  property voters : Hash(String, String) # user_id => option
  property status : String # active, closed
  property created_at : Time
  property end_time : Time?
  property percentages : Hash(String, Float64)
  
  def initialize(@title : String, options : Array(String))
    @options = options.to_h { |opt| {opt, 0} }
    @voters = {} of String => String
    @status = "active"
    @created_at = Time.local
    @end_time = nil
    @percentages = {} of String => Float64
    update_percentages
  end
  
  def vote(user_id : String, option : String) : Bool
    return false unless @status == "active"
    return false unless @options.has_key?(option)
    
    if previous = @voters[user_id]?
      @options[previous] -= 1
    end
    
    @options[option] += 1
    @voters[user_id] = option
    
    update_percentages
    
    true
  end
  
  private def update_percentages
    total = total_votes
    @percentages = @options.transform_values { |votes|
      total > 0 ? (votes * 100.0 / total) : 0.0
    }
  end
  
  def close
    @status = "closed"
    @end_time = Time.local
  end
  
  def total_votes : Int32
    @options.values.sum
  end
  
  def percentage(option : String) : Float64
    total = total_votes
    return 0.0 if total == 0
    (@options[option] * 100.0) / total
  end
  
  def to_json(json : JSON::Builder)
    json.object do
      json.field "title", @title
      json.field "options", @options
      json.field "voters", @voters
      json.field "status", @status
      json.field "created_at", @created_at
      json.field "end_time", @end_time
      json.field "total_votes", total_votes
      json.field "percentages", @percentages
    end
  end
end

# Crear encuesta inicial
poll = Poll.new(
  "¿Cuál es tu framework web favorito?",
  ["Ruby on Rails", "Django", "Laravel", "Express.js", "Phoenix"]
)

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "voters")
      
      socket.send({
        type: "init",
        poll: poll,
        your_vote: poll.voters[user_id]?
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "vote"
          if option = data["option"]?.try(&.as_s)
            if poll.vote(user_id, option)
              Hauyna::WebSocket::Events.send_to_group("voters", {
                type: "poll_update",
                poll: poll
              }.to_json)
            end
          end
        when "close_poll"
          poll.close
          Hauyna::WebSocket::Events.send_to_group("voters", {
            type: "poll_closed",
            poll: poll
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

  router.websocket("/vote", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Votación en Tiempo Real</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .chart-container {
              position: relative;
              height: 400px;
              margin: 20px 0;
            }
            .options {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 10px;
              margin: 20px 0;
            }
            .option {
              padding: 15px;
              border: 1px solid #ccc;
              border-radius: 4px;
              cursor: pointer;
              text-align: center;
              transition: all 0.3s ease;
              background: white;
            }
            .option:hover {
              background: #f5f5f5;
              transform: translateY(-2px);
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .option.selected {
              background: #e3f2fd;
              border-color: #2196F3;
              box-shadow: 0 2px 4px rgba(33,150,243,0.2);
            }
            .option strong {
              display: block;
              margin-top: 5px;
              color: #666;
            }
            .stats {
              display: flex;
              justify-content: space-between;
              margin: 20px 0;
              font-size: 18px;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1 id="title"></h1>
            <div class="stats">
              <div>Total votos: <span id="total-votes">0</span></div>
              <div id="status"></div>
            </div>
            <div class="chart-container">
              <canvas id="chart"></canvas>
            </div>
            <div id="options" class="options"></div>
            <div id="error"></div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/vote?user_id=\${userId}\`);
            let chart;
            let poll;
            
            function createChart(poll) {
              const ctx = document.getElementById('chart').getContext('2d');
              return new Chart(ctx, {
                type: 'bar',
                data: {
                  labels: Object.keys(poll.options),
                  datasets: [{
                    label: 'Votos',
                    data: Object.values(poll.options),
                    backgroundColor: [
                      '#FF6384',
                      '#36A2EB',
                      '#FFCE56',
                      '#4BC0C0',
                      '#9966FF'
                    ],
                    yAxisID: 'y'
                  }, {
                    label: 'Porcentaje',
                    data: Object.keys(poll.options).map(option => poll.percentages[option]),
                    type: 'line',
                    borderColor: '#4CAF50',
                    borderWidth: 2,
                    fill: false,
                    yAxisID: 'y1'
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  interaction: {
                    mode: 'index',
                    intersect: false,
                  },
                  scales: {
                    y: {
                      type: 'linear',
                      display: true,
                      position: 'left',
                      beginAtZero: true,
                      ticks: {
                        stepSize: 1
                      },
                      title: {
                        display: true,
                        text: 'Número de votos'
                      }
                    },
                    y1: {
                      type: 'linear',
                      display: true,
                      position: 'right',
                      beginAtZero: true,
                      max: 100,
                      ticks: {
                        callback: function(value) {
                          return value + '%';
                        }
                      },
                      title: {
                        display: true,
                        text: 'Porcentaje'
                      },
                      grid: {
                        drawOnChartArea: false
                      }
                    }
                  },
                  plugins: {
                    tooltip: {
                      callbacks: {
                        label: function(context) {
                          const value = context.raw;
                          if (context.dataset.label === 'Votos') {
                            const total = Object.values(poll.options).reduce((a, b) => a + b, 0);
                            const percentage = calculatePercentage(value, total);
                            return `${value} votos (${percentage.toFixed(1)}%)`;
                          } else {
                            return `${value.toFixed(1)}%`;
                          }
                        }
                      }
                    }
                  }
                }
              });
            }

            function calculatePercentage(votes, total) {
              return total > 0 ? (votes * 100 / total) : 0;
            }

            function updateUI(poll, yourVote = null) {
              document.getElementById('title').textContent = poll.title;
              document.getElementById('total-votes').textContent = poll.total_votes;
              document.getElementById('status').textContent = 
                poll.status === 'active' ? 'Votación en curso' : 'Votación cerrada';
              
              const options = document.getElementById('options');
              options.innerHTML = Object.entries(poll.options)
                .map(([option, votes]) => {
                  const percentage = poll.percentages[option];
                  return \`
                    <div class="option \${option === yourVote ? 'selected' : ''}"
                         onclick="vote('\${option}')"
                         \${poll.status === 'closed' ? 'style="pointer-events: none"' : ''}>
                      \${option}<br>
                      <strong>\${votes} votos (\${percentage.toFixed(1)}%)</strong>
                    </div>
                  \`;
                }).join('');
              
              if (chart) {
                chart.data.labels = Object.keys(poll.options);
                chart.data.datasets[0].data = Object.values(poll.options);
                chart.data.datasets[1].data = Object.keys(poll.options).map(option => 
                  poll.percentages[option]
                );
                chart.update();
              } else {
                chart = createChart(poll);
              }
            }

            function vote(option) {
              if (poll.status === 'active') {
                ws.send(JSON.stringify({
                  type: 'vote',
                  option: option
                }));
              }
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  poll = data.poll;
                  updateUI(data.poll, data.your_vote);
                  break;
                  
                case 'poll_update':
                case 'poll_closed':
                  poll = data.poll;
                  updateUI(data.poll, poll.voters[userId]);
                  break;
                  
                case 'error':
                  document.getElementById('error').textContent = data.message;
                  setTimeout(() => {
                    document.getElementById('error').textContent = '';
                  }, 3000);
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