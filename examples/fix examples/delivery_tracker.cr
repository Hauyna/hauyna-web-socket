require "../src/hauyna-web-socket"
require "http/server"

# Sistema de seguimiento de pedidos/delivery en tiempo real

class DeliveryPerson
  include JSON::Serializable
  
  property id : String
  property name : String
  property status : String # available, delivering, offline
  property current_location : Location?
  property current_order_id : String?
  
  def initialize(@name : String)
    @id = Random::Secure.hex(8)
    @status = "available"
    @current_location = nil
    @current_order_id = nil
  end
end

class Location
  include JSON::Serializable
  
  property lat : Float64
  property lng : Float64
  property timestamp : Time
  
  def initialize(@lat : Float64, @lng : Float64)
    @timestamp = Time.local
  end
end

class Order
  include JSON::Serializable
  
  property id : String
  property customer_id : String
  property customer_name : String
  property delivery_person_id : String?
  property status : String # pending, assigned, picked_up, delivered, cancelled
  property items : Array(OrderItem)
  property pickup_location : Location
  property delivery_location : Location
  property total : Float64
  property notes : String?
  property created_at : Time
  property estimated_time : Int32? # minutos
  property route_points : Array(Location)
  
  def initialize(@customer_id : String, @customer_name : String, @items : Array(OrderItem),
                @pickup_location : Location, @delivery_location : Location, @notes : String?)
    @id = Random::Secure.hex(8)
    @status = "pending"
    @delivery_person_id = nil
    @created_at = Time.local
    @estimated_time = nil
    @route_points = [] of Location
    @total = calculate_total
  end
  
  private def calculate_total : Float64
    @items.sum(&.subtotal)
  end
end

class OrderItem
  include JSON::Serializable
  
  property name : String
  property quantity : Int32
  property price : Float64
  property notes : String?
  
  def initialize(@name : String, @quantity : Int32, @price : Float64, @notes : String? = nil)
  end
  
  def subtotal : Float64
    @quantity * @price
  end
end

class DeliverySystem
  include JSON::Serializable
  
  property orders : Hash(String, Order)
  property delivery_people : Hash(String, DeliveryPerson)
  property users : Hash(String, String) # user_id => name
  property notifications : Array(String)
  
  def initialize
    @orders = {} of String => Order
    @delivery_people = {} of String => DeliveryPerson
    @users = {} of String => String
    @notifications = [] of String
    
    setup_demo_delivery_people
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
  
  def create_order(customer_id : String, items : Array(OrderItem), 
                  pickup_location : Location, delivery_location : Location, 
                  notes : String?) : Order
    order = Order.new(
      customer_id: customer_id,
      customer_name: @users[customer_id],
      items: items,
      pickup_location: pickup_location,
      delivery_location: delivery_location,
      notes: notes
    )
    
    @orders[order.id] = order
    add_notification("Nuevo pedido creado por #{order.customer_name}")
    order
  end
  
  def assign_delivery_person(order_id : String, delivery_person_id : String) : Bool
    order = @orders[order_id]?
    delivery_person = @delivery_people[delivery_person_id]?
    
    if order && delivery_person
      return false unless order.status == "pending"
      return false unless delivery_person.status == "available"
      
      order.status = "assigned"
      order.delivery_person_id = delivery_person_id
      order.estimated_time = calculate_estimated_time(order)
      
      delivery_person.status = "delivering"
      delivery_person.current_order_id = order_id
      
      add_notification("#{delivery_person.name} asignado al pedido de #{order.customer_name}")
      true
    else
      false
    end
  end
  
  def update_delivery_location(delivery_person_id : String, location : Location) : Bool
    if delivery_person = @delivery_people[delivery_person_id]?
      delivery_person.current_location = location
      
      if order_id = delivery_person.current_order_id
        if order = @orders[order_id]?
          order.route_points << location
        end
      end
      
      true
    else
      false
    end
  end
  
  def update_order_status(order_id : String, status : String) : Bool
    if order = @orders[order_id]?
      old_status = order.status
      order.status = status
      
      if status == "delivered" || status == "cancelled"
        if delivery_person = @delivery_people[order.delivery_person_id]?
          delivery_person.status = "available"
          delivery_person.current_order_id = nil
          delivery_person.current_location = nil
        end
      end
      
      add_notification("Pedido de #{order.customer_name} cambió de #{old_status} a #{status}")
      true
    else
      false
    end
  end
  
  private def add_notification(message : String)
    @notifications << "[#{Time.local}] #{message}"
    @notifications = @notifications.last(50)
  end
  
  private def calculate_estimated_time(order : Order) : Int32
    # Simulación simple de estimación
    base_time = 30 # 30 minutos base
    distance_factor = 5 # 5 minutos extra por cada km
    
    # Calcular distancia (simplificado)
    lat_diff = (order.delivery_location.lat - order.pickup_location.lat).abs
    lng_diff = (order.delivery_location.lng - order.pickup_location.lng).abs
    distance_km = Math.sqrt(lat_diff * lat_diff + lng_diff * lng_diff) * 111 # aprox km
    
    (base_time + (distance_km * distance_factor)).to_i
  end
  
  private def setup_demo_delivery_people
    ["Juan Repartidor", "María Delivery", "Carlos Express"].each do |name|
      person = DeliveryPerson.new(name)
      @delivery_people[person.id] = person
    end
  end
end

system = DeliverySystem.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        system.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
        
        socket.send({
          type: "init",
          system: system
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "create_order"
          items = data["items"].as_a.map { |item|
            OrderItem.new(
              name: item["name"].as_s,
              quantity: item["quantity"].as_i,
              price: item["price"].as_f,
              notes: item["notes"]?.try(&.as_s)
            )
          }
          
          pickup = Location.new(
            data["pickup_location"]["lat"].as_f,
            data["pickup_location"]["lng"].as_f
          )
          
          delivery = Location.new(
            data["delivery_location"]["lat"].as_f,
            data["delivery_location"]["lng"].as_f
          )
          
          order = system.create_order(
            user_id,
            items,
            pickup,
            delivery,
            data["notes"]?.try(&.as_s)
          )
          
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "system_update",
            system: system
          }.to_json)
          
        when "update_location"
          if system.update_delivery_location(
            user_id,
            Location.new(
              data["lat"].as_f,
              data["lng"].as_f
            )
          )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type: "system_update",
              system: system
            }.to_json)
          end
          
        when "update_order_status"
          if system.update_order_status(
            data["order_id"].as_s,
            data["status"].as_s
          )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type: "system_update",
              system: system
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

  # Simulación de asignación automática de repartidores
  spawn do
    loop do
      sleep 5.seconds
      
      pending_orders = system.orders.values.select { |o| o.status == "pending" }
      available_delivery = system.delivery_people.values.select { |d| d.status == "available" }
      
      pending_orders.each do |order|
        if !available_delivery.empty?
          delivery_person = available_delivery.sample
          system.assign_delivery_person(order.id, delivery_person.id)
          
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "system_update",
            system: system
          }.to_json)
        end
      end
    end
  end

  router.websocket("/delivery", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Seguimiento de Pedidos</title>
          <script src="https://maps.googleapis.com/maps/api/js?key=YOUR_API_KEY"></script>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .orders {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin: 20px 0;
            }
            .order-card {
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .map-container {
              height: 300px;
              margin: 10px 0;
              border-radius: 8px;
              overflow: hidden;
            }
            .status-pending { color: #f57f17; }
            .status-assigned { color: #1976d2; }
            .status-picked_up { color: #7b1fa2; }
            .status-delivered { color: #2e7d32; }
            .status-cancelled { color: #c62828; }
            .notifications {
              background: #fff3e0;
              padding: 15px;
              border-radius: 8px;
              margin: 20px 0;
            }
            .notification {
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
            .items-list {
              margin: 10px 0;
            }
            .item {
              display: flex;
              justify-content: space-between;
              padding: 5px 0;
              border-bottom: 1px solid #eee;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Sistema de Seguimiento de Pedidos</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinSystem()">Entrar</button>
            </div>
            
            <div id="delivery-system" style="display: none;">
              <h1>Seguimiento de Pedidos</h1>
              
              <div class="notifications">
                <h2>Notificaciones</h2>
                <div id="notifications"></div>
              </div>
              
              <button onclick="openNewOrderModal()">Nuevo Pedido</button>
              
              <div id="orders" class="orders"></div>
            </div>
          </div>
          
          <div id="new-order-modal" class="modal">
            <div class="modal-content">
              <h2>Nuevo Pedido</h2>
              <div id="items-form">
                <h3>Items</h3>
                <div id="items-list"></div>
                <button onclick="addItem()">Agregar Item</button>
              </div>
              <div>
                <h3>Ubicación de Recogida</h3>
                <div id="pickup-map" class="map-container"></div>
              </div>
              <div>
                <h3>Ubicación de Entrega</h3>
                <div id="delivery-map" class="map-container"></div>
              </div>
              <div>
                <label>Notas:</label>
                <textarea id="order-notes" rows="3"></textarea>
              </div>
              <button onclick="submitOrder()">Crear Pedido</button>
              <button onclick="closeModal()">Cancelar</button>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let system;
            let maps = {};
            let markers = {};
            let orderItems = [];
            let pickupLocation = null;
            let deliveryLocation = null;
            
            function initMap(elementId, clickable = true) {
              const map = new google.maps.Map(
                document.getElementById(elementId),
                {
                  center: { lat: 19.4326, lng: -99.1332 }, // Ciudad de México
                  zoom: 12
                }
              );
              
              if (clickable) {
                map.addListener('click', (e) => {
                  const location = {
                    lat: e.latLng.lat(),
                    lng: e.latLng.lng()
                  };
                  
                  if (elementId === 'pickup-map') {
                    pickupLocation = location;
                    updateMarker('pickup', location, map);
                  } else if (elementId === 'delivery-map') {
                    deliveryLocation = location;
                    updateMarker('delivery', location, map);
                  }
                });
              }
              
              maps[elementId] = map;
              return map;
            }
            
            function updateMarker(type, location, map) {
              if (markers[type]) {
                markers[type].setMap(null);
              }
              
              markers[type] = new google.maps.Marker({
                position: location,
                map: map,
                title: type === 'pickup' ? 'Recogida' : 'Entrega'
              });
            }
            
            function joinSystem() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('delivery-system').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/delivery?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function openNewOrderModal() {
              document.getElementById('new-order-modal').style.display = 'block';
              orderItems = [];
              updateItemsList();
              
              setTimeout(() => {
                if (!maps['pickup-map']) {
                  initMap('pickup-map');
                }
                if (!maps['delivery-map']) {
                  initMap('delivery-map');
                }
              }, 100);
            }
            
            function closeModal() {
              document.getElementById('new-order-modal').style.display = 'none';
              orderItems = [];
              pickupLocation = null;
              deliveryLocation = null;
            }
            
            function addItem() {
              orderItems.push({
                name: '',
                quantity: 1,
                price: 0,
                notes: ''
              });
              updateItemsList();
            }
            
            function updateItemsList() {
              const itemsList = document.getElementById('items-list');
              itemsList.innerHTML = orderItems.map((item, index) => \`
                <div class="item">
                  <input type="text" placeholder="Nombre" 
                         onchange="updateItem(\${index}, 'name', this.value)"
                         value="\${item.name}">
                  <input type="number" min="1" 
                         onchange="updateItem(\${index}, 'quantity', parseInt(this.value))"
                         value="\${item.quantity}">
                  <input type="number" step="0.01" min="0" 
                         onchange="updateItem(\${index}, 'price', parseFloat(this.value))"
                         value="\${item.price}">
                  <input type="text" placeholder="Notas" 
                         onchange="updateItem(\${index}, 'notes', this.value)"
                         value="\${item.notes || ''}">
                  <button onclick="removeItem(\${index})">X</button>
                </div>
              \`).join('');
            }
            
            function updateItem(index, field, value) {
              orderItems[index][field] = value;
            }
            
            function removeItem(index) {
              orderItems.splice(index, 1);
              updateItemsList();
            }
            
            function submitOrder() {
              if (!pickupLocation || !deliveryLocation || orderItems.length === 0) {
                alert('Por favor completa todos los campos');
                return;
              }
              
              ws.send(JSON.stringify({
                type: 'create_order',
                items: orderItems,
                pickup_location: pickupLocation,
                delivery_location: deliveryLocation,
                notes: document.getElementById('order-notes').value
              }));
              
              closeModal();
            }
            
            function updateOrderStatus(orderId, status) {
              ws.send(JSON.stringify({
                type: 'update_order_status',
                order_id: orderId,
                status: status
              }));
            }
            
            function updateUI() {
              // Actualizar pedidos
              const ordersDiv = document.getElementById('orders');
              ordersDiv.innerHTML = Object.values(system.orders)
                .filter(order => 
                  order.customer_id === userId || 
                  order.delivery_person_id === userId
                )
                .map(order => {
                  const deliveryPerson = order.delivery_person_id ? 
                    system.delivery_people[order.delivery_person_id] : null;
                  
                  return \`
                    <div class="order-card">
                      <div class="order-header">
                        <h3>Pedido #\${order.id}</h3>
                        <div class="status-\${order.status}">
                          \${order.status.toUpperCase()}
                        </div>
                      </div>
                      <div class="items-list">
                        \${order.items.map(item => \`
                          <div class="item">
                            <span>\${item.quantity}x \${item.name}</span>
                            <span>$\${(item.quantity * item.price).toFixed(2)}</span>
                          </div>
                        \`).join('')}
                        <div class="item">
                          <strong>Total:</strong>
                          <strong>$\${order.total.toFixed(2)}</strong>
                        </div>
                      </div>
                      \${deliveryPerson ? \`
                        <div>Repartidor: \${deliveryPerson.name}</div>
                        \${order.estimated_time ? \`
                          <div>Tiempo estimado: \${order.estimated_time} minutos</div>
                        \` : ''}
                      \` : ''}
                      <div class="map-container" id="map-\${order.id}"></div>
                      \${order.status === 'pending' && order.customer_id === userId ? \`
                        <button onclick="updateOrderStatus('\${order.id}', 'cancelled')">
                          Cancelar
                        </button>
                      \` : ''}
                      \${order.delivery_person_id === userId ? \`
                        <div>
                          <button onclick="updateOrderStatus('\${order.id}', 'picked_up')"
                                  \${order.status !== 'assigned' ? 'disabled' : ''}>
                            Recogido
                          </button>
                          <button onclick="updateOrderStatus('\${order.id}', 'delivered')"
                                  \${order.status !== 'picked_up' ? 'disabled' : ''}>
                            Entregado
                          </button>
                        </div>
                      \` : ''}
                    </div>
                  \`;
                }).join('');
              
              // Inicializar mapas de pedidos
              Object.values(system.orders)
                .filter(order => 
                  order.customer_id === userId || 
                  order.delivery_person_id === userId
                )
                .forEach(order => {
                  const mapId = \`map-\${order.id}\`;
                  if (!maps[mapId]) {
                    const map = initMap(mapId, false);
                    
                    // Marcadores de recogida y entrega
                    new google.maps.Marker({
                      position: order.pickup_location,
                      map: map,
                      title: 'Recogida',
                      icon: 'http://maps.google.com/mapfiles/ms/icons/green-dot.png'
                    });
                    
                    new google.maps.Marker({
                      position: order.delivery_location,
                      map: map,
                      title: 'Entrega',
                      icon: 'http://maps.google.com/mapfiles/ms/icons/red-dot.png'
                    });
                    
                    // Ruta del repartidor
                    if (order.route_points.length > 0) {
                      new google.maps.Polyline({
                        path: order.route_points,
                        map: map,
                        strokeColor: '#2196f3',
                        strokeWeight: 3
                      });
                      
                      // Marcador de posición actual
                      const currentPos = order.route_points[order.route_points.length - 1];
                      new google.maps.Marker({
                        position: currentPos,
                        map: map,
                        title: 'Repartidor',
                        icon: 'http://maps.google.com/mapfiles/ms/icons/blue-dot.png'
                      });
                    }
                    
                    // Centrar mapa
                    const bounds = new google.maps.LatLngBounds();
                    bounds.extend(order.pickup_location);
                    bounds.extend(order.delivery_location);
                    order.route_points.forEach(point => bounds.extend(point));
                    map.fitBounds(bounds);
                  }
                });
              
              // Actualizar notificaciones
              const notificationsDiv = document.getElementById('notifications');
              notificationsDiv.innerHTML = system.notifications
                .slice().reverse()
                .map(notification => \`
                  <div class="notification">\${notification}</div>
                \`).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                case 'system_update':
                  system = data.system;
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