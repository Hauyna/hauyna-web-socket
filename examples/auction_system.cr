require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de subastas en tiempo real

class Item
  include JSON::Serializable
  
  property id : String
  property name : String
  property description : String
  property starting_price : Float64
  property current_price : Float64
  property highest_bidder : String?
  property end_time : Time
  property status : String # active, ended
  
  def initialize(@id : String, @name : String, @description : String, @starting_price : Float64)
    @current_price = @starting_price
    @highest_bidder = nil
    @end_time = Time.local + 5.minutes
    @status = "active"
  end
  
  def place_bid(amount : Float64, bidder : String) : Bool
    return false if amount <= @current_price || Time.local > @end_time
    
    @current_price = amount
    @highest_bidder = bidder
    true
  end
  
  def time_remaining : Int32
    remaining = (@end_time - Time.local).total_seconds.to_i
    remaining > 0 ? remaining : 0
  end
end

# Crear algunos items de ejemplo
items = [
  Item.new("1", "Reloj Antiguo", "Reloj de péndulo del siglo XIX", 100.0),
  Item.new("2", "Pintura al Óleo", "Paisaje marino original", 500.0),
  Item.new("3", "Moneda Coleccionable", "Denario romano en buen estado", 250.0)
]

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["bidder_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if bidder_id = params["bidder_id"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.add_to_group(bidder_id, "bidders")
      socket.send({
        type: "init",
        items: items
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if bidder_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if data["type"]?.try(&.as_s) == "bid"
          item_id = data["item_id"].as_s
          amount = data["amount"].as_f
          
          if item = items.find { |i| i.id == item_id }
            if item.place_bid(amount, bidder_id)
              Hauyna::WebSocket::Events.send_to_group("bidders", {
                type: "bid_update",
                item: item
              }.to_json)
            else
              socket.send({
                type: "error",
                message: "Puja inválida o subasta terminada"
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

  # Actualizar tiempo restante y verificar subastas terminadas
  spawn do
    loop do
      items.each do |item|
        if item.status == "active" && item.time_remaining == 0
          item.status = "ended"
          Hauyna::WebSocket::Events.send_to_group("bidders", {
            type: "auction_ended",
            item: item
          }.to_json)
        end
      end
      
      Hauyna::WebSocket::Events.send_to_group("bidders", {
        type: "time_update",
        items: items.map { |i| {id: i.id, time: i.time_remaining} }
      }.to_json)
      
      sleep 1.seconds
    end
  end

  router.websocket("/auction", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Sistema de Subastas</title>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .item {
              border: 1px solid #ccc;
              padding: 15px;
              margin-bottom: 20px;
              border-radius: 4px;
            }
            .item.ended {
              opacity: 0.7;
              background: #f5f5f5;
            }
            .bid-form {
              display: flex;
              gap: 10px;
              margin-top: 10px;
            }
            .price {
              font-size: 20px;
              font-weight: bold;
              color: #2196F3;
            }
            .timer {
              color: #666;
            }
            .winner {
              color: #4CAF50;
              font-weight: bold;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Subastas en Vivo</h1>
            <div id="error"></div>
            <div id="items"></div>
          </div>

          <script>
            const bidderId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/auction?bidder_id=\${bidderId}\`);
            const items = document.getElementById('items');
            const error = document.getElementById('error');

            function formatTime(seconds) {
              const mins = Math.floor(seconds / 60);
              const secs = seconds % 60;
              return \`\${mins}:\${secs.toString().padStart(2, '0')}\`;
            }

            function updateItem(item) {
              const itemElement = document.getElementById(\`item-\${item.id}\`);
              if (itemElement) {
                itemElement.className = \`item \${item.status}\`;
                itemElement.querySelector('.price').textContent = 
                  \`Precio actual: $\${item.current_price.toFixed(2)}\`;
                itemElement.querySelector('.highest-bidder').textContent = 
                  item.highest_bidder ? \`Mayor postor: \${item.highest_bidder === bidderId ? 'Tú' : item.highest_bidder}\` : '';
              }
            }

            function createItemElement(item) {
              const div = document.createElement('div');
              div.id = \`item-\${item.id}\`;
              div.className = \`item \${item.status}\`;
              div.innerHTML = \`
                <h2>\${item.name}</h2>
                <p>\${item.description}</p>
                <div class="price">Precio actual: $\${item.current_price.toFixed(2)}</div>
                <div class="highest-bidder">\${
                  item.highest_bidder ? 
                    \`Mayor postor: \${item.highest_bidder === bidderId ? 'Tú' : item.highest_bidder}\` : 
                    ''
                }</div>
                <div class="timer" id="timer-\${item.id}"></div>
                \${item.status === 'active' ? \`
                  <div class="bid-form">
                    <input type="number" step="0.01" min="\${item.current_price + 0.01}" 
                           id="bid-\${item.id}" placeholder="Tu puja">
                    <button onclick="placeBid('\${item.id}')">Pujar</button>
                  </div>
                \` : ''}
              \`;
              return div;
            }

            function placeBid(itemId) {
              const input = document.getElementById(\`bid-\${itemId}\`);
              const amount = parseFloat(input.value);
              if (amount) {
                ws.send(JSON.stringify({
                  type: 'bid',
                  item_id: itemId,
                  amount: amount
                }));
                input.value = '';
              }
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  items.innerHTML = '';
                  data.items.forEach(item => {
                    items.appendChild(createItemElement(item));
                  });
                  break;
                  
                case 'bid_update':
                  updateItem(data.item);
                  break;
                  
                case 'auction_ended':
                  updateItem(data.item);
                  const itemElement = document.getElementById(\`item-\${data.item.id}\`);
                  if (itemElement) {
                    const winner = data.item.highest_bidder === bidderId ? 'Tú' : data.item.highest_bidder;
                    itemElement.querySelector('.bid-form')?.remove();
                    itemElement.insertAdjacentHTML('beforeend', \`
                      <div class="winner">
                        ¡Subasta terminada! Ganador: \${winner}
                      </div>
                    \`);
                  }
                  break;
                  
                case 'time_update':
                  data.items.forEach(item => {
                    const timer = document.getElementById(\`timer-\${item.id}\`);
                    if (timer) {
                      timer.textContent = \`Tiempo restante: \${formatTime(item.time)}\`;
                    }
                  });
                  break;
                  
                case 'error':
                  error.textContent = data.message;
                  setTimeout(() => error.textContent = '', 3000);
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