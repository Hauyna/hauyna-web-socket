require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de subastas en tiempo real

class BaseMessage
  include JSON::Serializable
  
  property type : String
  
  def initialize(@type)
  end
end

class InitMessage < BaseMessage
  property items : Array(ItemMessage)
  
  def initialize(@items)
    super("init")
  end
end

class BidUpdateMessage < BaseMessage
  property item : ItemMessage
  
  def initialize(@item)
    super("bid_update")
  end
end

class TimeUpdateMessage < BaseMessage
  property items : Array(TimeItemMessage)
  
  def initialize(@items)
    super("time_update")
  end
end

class TimeItemMessage
  include JSON::Serializable
  
  property id : String
  property time : Int32
  
  def initialize(@id, @time)
  end
end

class ItemMessage
  include JSON::Serializable
  
  property id : String
  property name : String
  property description : String
  property starting_price : String
  property current_price : String
  property highest_bidder : String
  property end_time : Int64
  property status : String
  
  def initialize(@id, @name, @description, @starting_price, @current_price, @highest_bidder, @end_time, @status)
  end
  
  def self.from_item(item : Item)
    new(
      id: item.id,
      name: item.name,
      description: item.description,
      starting_price: item.starting_price.to_s,
      current_price: item.current_price.to_s,
      highest_bidder: item.highest_bidder || "",
      end_time: item.end_time.to_unix,
      status: item.status
    )
  end
end

class ErrorMessage < BaseMessage
  property message : String
  
  def initialize(@message)
    super("error")
  end
end

class BidMessage < BaseMessage
  property item_id : String
  property amount : Float64
  
  def initialize(@item_id, @amount)
    super("bid")
  end
end

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
  
  def to_json_object : Hash(String, String | Float64 | Int64)
    {
      "id" => @id,
      "name" => @name,
      "description" => @description,
      "starting_price" => @starting_price,
      "current_price" => @current_price,
      "highest_bidder" => @highest_bidder || "",
      "end_time" => @end_time.to_unix.to_i64,
      "status" => @status
    }
  end
  
  def time_update_object : Hash(String, String | Int32)
    {
      "id" => @id,
      "time" => time_remaining
    }
  end
  
  def place_bid(amount : Float64, bidder : String) : Bool
    return false if amount <= @current_price || Time.local > @end_time || @status != "active"
    
    @current_price = amount
    @highest_bidder = bidder
    true
  end
  
  def time_remaining : Int32
    remaining = (@end_time - Time.local).total_seconds.to_i
    remaining > 0 ? remaining : 0
  end

  def broadcast_update(type : String)
    case type
    when "bid_update"
      message = BidUpdateMessage.new(ItemMessage.from_item(self))
      Hauyna::WebSocket::Events.send_to_group("bidders", message.to_json)
    when "auction_ended"
      message = BidUpdateMessage.new(ItemMessage.from_item(self))
      Hauyna::WebSocket::Events.send_to_group("bidders", message.to_json)
    end
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
      message = InitMessage.new(items.map { |item| ItemMessage.from_item(item) })
      socket.send(message.to_json)
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
              item.broadcast_update("bid_update")
            else
              error_message = ErrorMessage.new("Puja inválida o subasta terminada")
              socket.send(error_message.to_json)
            end
          end
        end
      rescue ex
        puts "Error en puja: #{ex.message}" # Debug
        error_message = ErrorMessage.new("Error al procesar la puja")
        socket.send(error_message.to_json)
      end
    end
  }

  # Actualizar tiempo restante y verificar subastas terminadas
  spawn do
    loop do
      items.each do |item|
        if item.status == "active" && item.time_remaining == 0
          item.status = "ended"
          item.broadcast_update("auction_ended")
        end
      end
      
      time_items = items.map { |item| TimeItemMessage.new(item.id, item.time_remaining) }
      message = TimeUpdateMessage.new(time_items)
      Hauyna::WebSocket::Events.send_to_group("bidders", message.to_json)
      
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
                const currentPrice = typeof item.current_price === 'string' ? 
                  parseFloat(item.current_price) : item.current_price;
                
                itemElement.querySelector('.price').textContent = 
                  \`Precio actual: $\${currentPrice.toFixed(2)}\`;
                  
                const highestBidder = item.highest_bidder === "" ? null : item.highest_bidder;
                itemElement.querySelector('.highest-bidder').textContent = 
                  highestBidder ? \`Mayor postor: \${highestBidder === bidderId ? 'Tú' : highestBidder}\` : '';
              }
            }

            function createItemElement(item) {
              const div = document.createElement('div');
              div.id = \`item-\${item.id}\`;
              div.className = \`item \${item.status}\`;
              
              const currentPrice = typeof item.current_price === 'string' ? 
                parseFloat(item.current_price) : item.current_price;
              const highestBidder = item.highest_bidder === "" ? null : item.highest_bidder;
              
              div.innerHTML = \`
                <h2>\${item.name}</h2>
                <p>\${item.description}</p>
                <div class="price">Precio actual: $\${currentPrice.toFixed(2)}</div>
                <div class="highest-bidder">\${
                  highestBidder ? 
                    \`Mayor postor: \${highestBidder === bidderId ? 'Tú' : highestBidder}\` : 
                    ''
                }</div>
                <div class="timer" id="timer-\${item.id}"></div>
                \${item.status === 'active' ? \`
                  <div class="bid-form">
                    <input type="number" step="0.01" min="\${currentPrice + 0.01}" 
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
              if (!isNaN(amount) && amount > 0) {
                ws.send(JSON.stringify({
                  type: 'bid',
                  item_id: itemId,
                  amount: amount
                }));
                input.value = '';
              } else {
                error.textContent = 'Por favor ingresa una cantidad válida';
                setTimeout(() => error.textContent = '', 3000);
              }
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              console.log('Received message:', data); // Debug
              
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