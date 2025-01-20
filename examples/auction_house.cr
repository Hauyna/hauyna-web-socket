require "../src/hauyna-web-socket"
require "http/server"

# Sistema de subastas en tiempo real con pujas automáticas

class Item
  include JSON::Serializable
  
  property id : String
  property name : String
  property description : String
  property image_url : String
  property starting_price : Float64
  property current_price : Float64
  property min_increment : Float64
  property highest_bidder : String?
  property auto_bidders : Hash(String, Float64) # user_id => max_bid
  property end_time : Time
  property status : String # active, ended
  
  def initialize(@name : String, @description : String, @image_url : String, @starting_price : Float64, @min_increment : Float64, duration_minutes : Int32)
    @id = Random::Secure.hex(8)
    @current_price = @starting_price
    @highest_bidder = nil
    @auto_bidders = {} of String => Float64
    @end_time = Time.local + Time::Span.new(minutes: duration_minutes)
    @status = "active"
  end
  
  def place_bid(user_id : String, amount : Float64, max_amount : Float64? = nil) : Bool
    return false if @status != "active" || Time.local > @end_time
    return false if amount <= @current_price
    return false if amount < @current_price + @min_increment
    
    if max_amount
      @auto_bidders[user_id] = max_amount
    else
      @auto_bidders.delete(user_id)
    end
    
    @current_price = amount
    @highest_bidder = user_id
    
    process_auto_bids
    true
  end
  
  private def process_auto_bids
    loop do
      highest_auto = @auto_bidders.reject { |id, _| id == @highest_bidder }
        .max_by? { |_, max| max }
      
      break unless highest_auto
      break if highest_auto[1] <= @current_price + @min_increment
      
      new_amount = [@current_price + @min_increment, highest_auto[1]].min
      @current_price = new_amount
      @highest_bidder = highest_auto[0]
    end
  end
  
  def time_remaining : Int32
    remaining = (@end_time - Time.local).total_seconds.to_i
    remaining > 0 ? remaining : 0
  end
end

class AuctionHouse
  include JSON::Serializable
  
  property items : Hash(String, Item)
  property users : Hash(String, String) # user_id => name
  
  def initialize
    @items = {} of String => Item
    @users = {} of String => String
  end
  
  def add_item(item : Item)
    @items[item.id] = item
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
end

# Crear casa de subastas con items de ejemplo
auction = AuctionHouse.new
auction.add_item(Item.new(
  "Reloj Antiguo",
  "Reloj de péndulo del siglo XIX en excelente estado",
  "https://example.com/clock.jpg",
  100.0,
  5.0,
  60
))
auction.add_item(Item.new(
  "Pintura al Óleo",
  "Paisaje marino original, firmado por el artista",
  "https://example.com/painting.jpg",
  500.0,
  25.0,
  120
))

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        auction.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "bidders")
        
        socket.send({
          type: "init",
          auction: auction
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "bid"
          if item = auction.items[data["item_id"].as_s]?
            amount = data["amount"].as_f
            max_amount = data["max_amount"]?.try(&.as_f)
            
            if item.place_bid(user_id, amount, max_amount)
              Hauyna::WebSocket::Events.send_to_group("bidders", {
                type: "item_update",
                item: item
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

  # Temporizador para actualizar tiempos y cerrar subastas
  spawn do
    loop do
      sleep 1.seconds
      
      auction.items.each_value do |item|
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
        items: auction.items.transform_values(&.time_remaining)
      }.to_json)
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
          <title>Casa de Subastas</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .items {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
            }
            .item {
              border: 1px solid #ccc;
              border-radius: 8px;
              padding: 15px;
            }
            .item.ended {
              opacity: 0.7;
              background: #f5f5f5;
            }
            .item-image {
              width: 100%;
              height: 200px;
              object-fit: cover;
              border-radius: 4px;
              margin-bottom: 10px;
            }
            .item-title {
              font-size: 20px;
              font-weight: bold;
              margin-bottom: 10px;
            }
            .item-description {
              color: #666;
              margin-bottom: 10px;
            }
            .bid-form {
              margin-top: 15px;
              padding-top: 15px;
              border-top: 1px solid #eee;
            }
            .current-price {
              font-size: 24px;
              color: #2196F3;
              margin-bottom: 10px;
            }
            .highest-bidder {
              color: #4CAF50;
              margin-bottom: 10px;
            }
            .timer {
              color: #f44336;
              font-weight: bold;
            }
            .auto-bid {
              margin-top: 10px;
              padding: 10px;
              background: #f5f5f5;
              border-radius: 4px;
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
              <h2>Unirse a la Subasta</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinAuction()">Entrar</button>
            </div>
            
            <div id="auction-house" style="display: none;">
              <h1>Subastas en Curso</h1>
              <div id="items" class="items"></div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let auction;
            
            function formatTime(seconds) {
              const mins = Math.floor(seconds / 60);
              const secs = seconds % 60;
              return \`\${mins}:\${secs.toString().padStart(2, '0')}\`;
            }
            
            function formatPrice(price) {
              return price.toFixed(2);
            }
            
            function placeBid(itemId) {
              const amount = parseFloat(document.getElementById(\`bid-\${itemId}\`).value);
              const maxAmount = parseFloat(document.getElementById(\`max-bid-\${itemId}\`).value || 0);
              
              if (amount) {
                ws.send(JSON.stringify({
                  type: 'bid',
                  item_id: itemId,
                  amount: amount,
                  max_amount: maxAmount || null
                }));
              }
            }
            
            function updateItems() {
              const itemsDiv = document.getElementById('items');
              itemsDiv.innerHTML = Object.values(auction.items)
                .map(item => \`
                  <div class="item \${item.status === 'ended' ? 'ended' : ''}">
                    <img src="\${item.image_url}" class="item-image">
                    <div class="item-title">\${item.name}</div>
                    <div class="item-description">\${item.description}</div>
                    <div class="current-price">
                      Precio actual: $\${formatPrice(item.current_price)}
                    </div>
                    \${item.highest_bidder ? \`
                      <div class="highest-bidder">
                        Mejor postor: \${auction.users[item.highest_bidder]}
                      </div>
                    \` : ''}
                    <div class="timer" id="timer-\${item.id}"></div>
                    \${item.status === 'active' ? \`
                      <div class="bid-form">
                        <input type="number" id="bid-\${item.id}"
                               min="\${item.current_price + item.min_increment}"
                               step="\${item.min_increment}"
                               placeholder="Tu puja">
                        <button onclick="placeBid('\${item.id}')">Pujar</button>
                        <div class="auto-bid">
                          <div>Puja automática (opcional)</div>
                          <input type="number" id="max-bid-\${item.id}"
                                 placeholder="Puja máxima">
                        </div>
                      </div>
                    \` : ''}
                  </div>
                \`).join('');
            }
            
            function joinAuction() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('auction-house').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/auction?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                
                switch(data.type) {
                  case 'init':
                    auction = data.auction;
                    updateItems();
                    break;
                    
                  case 'item_update':
                    auction.items[data.item.id] = data.item;
                    updateItems();
                    break;
                    
                  case 'auction_ended':
                    auction.items[data.item.id] = data.item;
                    updateItems();
                    if (data.item.highest_bidder === userId) {
                      alert(\`¡Felicidades! Has ganado la subasta de \${data.item.name}\`);
                    }
                    break;
                    
                  case 'time_update':
                    Object.entries(data.items).forEach(([id, time]) => {
                      const timer = document.getElementById(\`timer-\${id}\`);
                      if (timer) {
                        timer.textContent = \`Tiempo restante: \${formatTime(time)}\`;
                      }
                    });
                    break;
                    
                  case 'error':
                    console.error(data.message);
                    break;
                }
              };
            }
          </script>
        </body>
      </html>
    HTML
  end
end

puts "Servidor iniciado en http://localhost:8080"
server.listen("0.0.0.0", 8080) 