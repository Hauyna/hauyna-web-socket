require "../src/hauyna-web-socket"
require "http/server"

# Sistema de control de inventario en tiempo real

class Product
  include JSON::Serializable
  
  property id : String
  property name : String
  property category : String
  property quantity : Int32
  property min_stock : Int32
  property price : Float64
  property location : String
  property last_updated : Time
  property status : String # in_stock, low_stock, out_of_stock
  
  def initialize(@name : String, @category : String, @quantity : Int32, @min_stock : Int32, @price : Float64, @location : String)
    @id = Random::Secure.hex(8)
    @last_updated = Time.local
    @status = calculate_status
  end
  
  def calculate_status : String
    if @quantity <= 0
      "out_of_stock"
    elsif @quantity <= @min_stock
      "low_stock"
    else
      "in_stock"
    end
  end
end

class Transaction
  include JSON::Serializable
  
  property id : String
  property product_id : String
  property type : String # add, remove, adjust
  property quantity : Int32
  property user_id : String
  property timestamp : Time
  property notes : String?
  
  def initialize(@product_id : String, @type : String, @quantity : Int32, @user_id : String, @notes : String? = nil)
    @id = Random::Secure.hex(8)
    @timestamp = Time.local
  end
end

class Inventory
  include JSON::Serializable
  
  property products : Hash(String, Product)
  property transactions : Array(Transaction)
  property users : Hash(String, String) # user_id => name
  property alerts : Array(String)
  
  def initialize
    @products = {} of String => Product
    @transactions = [] of Transaction
    @users = {} of String => String
    @alerts = [] of String
    
    setup_demo_products
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
  
  def update_product(product_id : String, quantity : Int32, type : String, user_id : String, notes : String? = nil) : Bool
    if product = @products[product_id]?
      old_quantity = product.quantity
      
      case type
      when "add"
        product.quantity += quantity
      when "remove"
        return false if product.quantity < quantity
        product.quantity -= quantity
      when "adjust"
        product.quantity = quantity
      else
        return false
      end
      
      product.status = product.calculate_status
      product.last_updated = Time.local
      
      transaction = Transaction.new(
        product_id: product_id,
        type: type,
        quantity: quantity,
        user_id: user_id,
        notes: notes
      )
      
      @transactions << transaction
      
      check_alerts(product)
      true
    else
      false
    end
  end
  
  private def check_alerts(product : Product)
    if product.quantity <= 0
      add_alert("#{product.name} está agotado")
    elsif product.quantity <= product.min_stock
      add_alert("#{product.name} está por debajo del stock mínimo (#{product.quantity} unidades)")
    end
  end
  
  private def add_alert(message : String)
    @alerts << "[#{Time.local}] #{message}"
    @alerts = @alerts.last(50) # Mantener solo las últimas 50 alertas
  end
  
  private def setup_demo_products
    [
      {
        name: "Laptop Dell XPS",
        category: "Electrónicos",
        quantity: 15,
        min_stock: 5,
        price: 1299.99,
        location: "A-123"
      },
      {
        name: "Monitor LG 27\"",
        category: "Electrónicos",
        quantity: 8,
        min_stock: 3,
        price: 299.99,
        location: "A-124"
      },
      {
        name: "Teclado Mecánico",
        category: "Accesorios",
        quantity: 25,
        min_stock: 10,
        price: 89.99,
        location: "B-101"
      },
      {
        name: "Mouse Inalámbrico",
        category: "Accesorios",
        quantity: 30,
        min_stock: 15,
        price: 39.99,
        location: "B-102"
      }
    ].each do |p|
      product = Product.new(
        name: p[:name],
        category: p[:category],
        quantity: p[:quantity],
        min_stock: p[:min_stock],
        price: p[:price],
        location: p[:location]
      )
      @products[product.id] = product
    end
  end
end

inventory = Inventory.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        inventory.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
        
        socket.send({
          type: "init",
          inventory: inventory
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "update_product"
          if inventory.update_product(
            data["product_id"].as_s,
            data["quantity"].as_i,
            data["action"].as_s,
            user_id,
            data["notes"]?.try(&.as_s)
          )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type: "inventory_update",
              inventory: inventory
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

  router.websocket("/inventory", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Control de Inventario</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .grid {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin: 20px 0;
            }
            .product-card {
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .product-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 15px;
            }
            .product-status {
              padding: 5px 10px;
              border-radius: 15px;
              font-size: 14px;
            }
            .in_stock { background: #c8e6c9; color: #2e7d32; }
            .low_stock { background: #fff9c4; color: #f57f17; }
            .out_of_stock { background: #ffcdd2; color: #c62828; }
            .transactions {
              margin-top: 20px;
            }
            .transaction {
              padding: 10px;
              border-bottom: 1px solid #eee;
            }
            .alerts {
              background: #fff3e0;
              padding: 15px;
              border-radius: 8px;
              margin: 20px 0;
            }
            .alert {
              color: #e65100;
              margin: 5px 0;
            }
            .modal {
              display: none;
              position: fixed;
              top: 0;
              left: 0;
              width: 100%;
              height: 100%;
              background: rgba(0,0,0,0.5);
            }
            .modal-content {
              background: white;
              padding: 20px;
              border-radius: 8px;
              width: 80%;
              max-width: 500px;
              margin: 50px auto;
            }
            .form-group {
              margin: 15px 0;
            }
            label {
              display: block;
              margin-bottom: 5px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Control de Inventario</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinSystem()">Entrar</button>
            </div>
            
            <div id="inventory-system" style="display: none;">
              <h1>Control de Inventario</h1>
              
              <div class="alerts">
                <h2>Alertas</h2>
                <div id="alerts"></div>
              </div>
              
              <div id="products" class="grid"></div>
              
              <div class="transactions">
                <h2>Últimas Transacciones</h2>
                <div id="transactions"></div>
              </div>
            </div>
          </div>
          
          <div id="update-modal" class="modal">
            <div class="modal-content">
              <h2>Actualizar Producto</h2>
              <div class="form-group">
                <label>Acción</label>
                <select id="action">
                  <option value="add">Agregar</option>
                  <option value="remove">Remover</option>
                  <option value="adjust">Ajustar</option>
                </select>
              </div>
              <div class="form-group">
                <label>Cantidad</label>
                <input type="number" id="quantity" min="0">
              </div>
              <div class="form-group">
                <label>Notas</label>
                <textarea id="notes"></textarea>
              </div>
              <button onclick="submitUpdate()">Actualizar</button>
              <button onclick="closeModal()">Cancelar</button>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let inventory;
            let selectedProduct;
            
            function joinSystem() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('inventory-system').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/inventory?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function openUpdateModal(productId) {
              selectedProduct = productId;
              document.getElementById('update-modal').style.display = 'block';
            }
            
            function closeModal() {
              document.getElementById('update-modal').style.display = 'none';
              selectedProduct = null;
            }
            
            function submitUpdate() {
              const action = document.getElementById('action').value;
              const quantity = parseInt(document.getElementById('quantity').value);
              const notes = document.getElementById('notes').value;
              
              if (!quantity || quantity < 0) return;
              
              ws.send(JSON.stringify({
                type: 'update_product',
                product_id: selectedProduct,
                action: action,
                quantity: quantity,
                notes: notes
              }));
              
              closeModal();
            }
            
            function updateUI() {
              // Actualizar productos
              const productsDiv = document.getElementById('products');
              productsDiv.innerHTML = Object.values(inventory.products)
                .map(product => \`
                  <div class="product-card">
                    <div class="product-header">
                      <h3>\${product.name}</h3>
                      <span class="product-status \${product.status}">
                        \${product.status.replace('_', ' ')}
                      </span>
                    </div>
                    <div>Categoría: \${product.category}</div>
                    <div>Cantidad: \${product.quantity}</div>
                    <div>Stock Mínimo: \${product.min_stock}</div>
                    <div>Precio: $\${product.price.toFixed(2)}</div>
                    <div>Ubicación: \${product.location}</div>
                    <button onclick="openUpdateModal('\${product.id}')">
                      Actualizar Stock
                    </button>
                  </div>
                \`).join('');
              
              // Actualizar transacciones
              const transactionsDiv = document.getElementById('transactions');
              transactionsDiv.innerHTML = inventory.transactions
                .slice().reverse()
                .map(t => {
                  const product = inventory.products[t.product_id];
                  return \`
                    <div class="transaction">
                      [\${new Date(t.timestamp).toLocaleString()}]
                      \${inventory.users[t.user_id]} 
                      \${t.type === 'add' ? 'agregó' : t.type === 'remove' ? 'removió' : 'ajustó'}
                      \${t.quantity} unidades de \${product.name}
                      \${t.notes ? \`(\${t.notes})\` : ''}
                    </div>
                  \`;
                }).join('');
              
              // Actualizar alertas
              const alertsDiv = document.getElementById('alerts');
              alertsDiv.innerHTML = inventory.alerts
                .slice().reverse()
                .map(alert => \`
                  <div class="alert">\${alert}</div>
                \`).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                case 'inventory_update':
                  inventory = data.inventory;
                  updateUI();
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