require "../src/hauyna-web-socket"
require "http/server"

# Sistema de reservas de restaurante en tiempo real

class Table
  include JSON::Serializable
  
  property id : Int32
  property seats : Int32
  property location : String # window, terrace, indoor
  property status : String # available, reserved, occupied
  property reservation : Reservation?
  
  def initialize(@id : Int32, @seats : Int32, @location : String)
    @status = "available"
    @reservation = nil
  end
end

class Reservation
  include JSON::Serializable
  
  property id : String
  property customer_id : String
  property customer_name : String
  property guests : Int32
  property date : String
  property time_slot : String
  property special_requests : String
  property status : String # pending, confirmed, cancelled, completed
  property created_at : Time
  
  def initialize(@customer_id : String, @customer_name : String, @guests : Int32, @date : String, @time_slot : String, @special_requests : String)
    @id = Random::Secure.hex(8)
    @status = "pending"
    @created_at = Time.local
  end
end

class Restaurant
  include JSON::Serializable
  
  TIME_SLOTS = ["18:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00", "21:30", "22:00"]
  
  property tables : Array(Table)
  property reservations : Hash(String, Reservation)
  property users : Hash(String, String) # user_id => name
  
  def initialize
    @tables = [] of Table
    @reservations = {} of String => Reservation
    @users = {} of String => String
    
    # Crear mesas de ejemplo
    [
      {id: 1, seats: 2, location: "window"},
      {id: 2, seats: 2, location: "window"},
      {id: 3, seats: 4, location: "indoor"},
      {id: 4, seats: 4, location: "indoor"},
      {id: 5, seats: 6, location: "terrace"},
      {id: 6, seats: 8, location: "terrace"}
    ].each do |t|
      @tables << Table.new(t[:id], t[:seats], t[:location])
    end
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
  
  def available_tables(date : String, time_slot : String, guests : Int32) : Array(Table)
    @tables.select do |table|
      table.status == "available" &&
      table.seats >= guests &&
      table.seats <= guests + 2 # No asignar mesas muy grandes
    end
  end
  
  def make_reservation(customer_id : String, customer_name : String, table_id : Int32, guests : Int32, date : String, time_slot : String, special_requests : String) : Reservation?
    return nil unless TIME_SLOTS.includes?(time_slot)
    
    if table = @tables.find { |t| t.id == table_id }
      return nil unless table.status == "available"
      
      reservation = Reservation.new(
        customer_id,
        customer_name,
        guests,
        date,
        time_slot,
        special_requests
      )
      
      @reservations[reservation.id] = reservation
      table.reservation = reservation
      table.status = "reserved"
      
      reservation
    end
  end
  
  def cancel_reservation(reservation_id : String) : Bool
    if reservation = @reservations[reservation_id]?
      if table = @tables.find { |t| t.reservation.try(&.id) == reservation_id }
        table.status = "available"
        table.reservation = nil
      end
      
      reservation.status = "cancelled"
      true
    else
      false
    end
  end
end

restaurant = Restaurant.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        restaurant.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "customers")
        
        socket.send({
          type: "init",
          restaurant: restaurant
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "check_availability"
          available = restaurant.available_tables(
            data["date"].as_s,
            data["time_slot"].as_s,
            data["guests"].as_i
          )
          
          socket.send({
            type: "availability_result",
            tables: available
          }.to_json)
          
        when "make_reservation"
          if reservation = restaurant.make_reservation(
            user_id,
            restaurant.users[user_id],
            data["table_id"].as_i,
            data["guests"].as_i,
            data["date"].as_s,
            data["time_slot"].as_s,
            data["special_requests"].as_s
          )
            Hauyna::WebSocket::Events.send_to_group("customers", {
              type: "table_update",
              tables: restaurant.tables
            }.to_json)
            
            socket.send({
              type: "reservation_confirmed",
              reservation: reservation
            }.to_json)
          end
          
        when "cancel_reservation"
          if restaurant.cancel_reservation(data["reservation_id"].as_s)
            Hauyna::WebSocket::Events.send_to_group("customers", {
              type: "table_update",
              tables: restaurant.tables
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

  router.websocket("/booking", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Reservas de Restaurante</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .booking-form {
              max-width: 600px;
              margin: 0 auto;
            }
            .form-group {
              margin-bottom: 15px;
            }
            .form-group label {
              display: block;
              margin-bottom: 5px;
            }
            .form-group input,
            .form-group select,
            .form-group textarea {
              width: 100%;
              padding: 8px;
              border: 1px solid #ddd;
              border-radius: 4px;
            }
            .tables {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
              gap: 20px;
              margin-top: 20px;
            }
            .table {
              border: 1px solid #ccc;
              padding: 15px;
              border-radius: 4px;
              text-align: center;
            }
            .table.available {
              background: #e8f5e9;
              cursor: pointer;
            }
            .table.reserved {
              background: #ffebee;
              opacity: 0.7;
            }
            .table:hover {
              transform: translateY(-2px);
            }
            .reservations {
              margin-top: 40px;
            }
            .reservation {
              border: 1px solid #eee;
              padding: 15px;
              margin-bottom: 10px;
              border-radius: 4px;
            }
            .reservation-header {
              display: flex;
              justify-content: space-between;
              margin-bottom: 10px;
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
              <h2>Sistema de Reservas</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinSystem()">Entrar</button>
            </div>
            
            <div id="booking-system" style="display: none;">
              <div class="booking-form">
                <h2>Nueva Reserva</h2>
                <div class="form-group">
                  <label>Fecha</label>
                  <input type="date" id="date" min="\${new Date().toISOString().split('T')[0]}">
                </div>
                <div class="form-group">
                  <label>Hora</label>
                  <select id="time_slot">
                    \${Restaurant.TIME_SLOTS.map(slot => 
                      \`<option value="\${slot}">\${slot}</option>\`
                    ).join('')}
                  </select>
                </div>
                <div class="form-group">
                  <label>Número de comensales</label>
                  <input type="number" id="guests" min="1" max="8" value="2">
                </div>
                <button onclick="checkAvailability()">Buscar mesas disponibles</button>
                
                <div id="tables" class="tables"></div>
                
                <div id="reservation-form" style="display: none;">
                  <div class="form-group">
                    <label>Peticiones especiales</label>
                    <textarea id="special_requests"></textarea>
                  </div>
                  <button onclick="makeReservation()">Confirmar Reserva</button>
                </div>
              </div>
              
              <div class="reservations">
                <h2>Mis Reservas</h2>
                <div id="my-reservations"></div>
              </div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let restaurant;
            let selectedTable = null;
            
            function joinSystem() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('booking-system').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/booking?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function checkAvailability() {
              const date = document.getElementById('date').value;
              const timeSlot = document.getElementById('time_slot').value;
              const guests = parseInt(document.getElementById('guests').value);
              
              if (!date) return;
              
              ws.send(JSON.stringify({
                type: 'check_availability',
                date: date,
                time_slot: timeSlot,
                guests: guests
              }));
            }
            
            function selectTable(tableId) {
              selectedTable = tableId;
              document.getElementById('reservation-form').style.display = 'block';
              
              document.querySelectorAll('.table').forEach(el => {
                el.style.border = el.dataset.id === tableId.toString() ?
                  '2px solid #2196F3' : '1px solid #ccc';
              });
            }
            
            function makeReservation() {
              if (!selectedTable) return;
              
              ws.send(JSON.stringify({
                type: 'make_reservation',
                table_id: selectedTable,
                date: document.getElementById('date').value,
                time_slot: document.getElementById('time_slot').value,
                guests: parseInt(document.getElementById('guests').value),
                special_requests: document.getElementById('special_requests').value
              }));
            }
            
            function cancelReservation(reservationId) {
              if (confirm('¿Estás seguro de que quieres cancelar esta reserva?')) {
                ws.send(JSON.stringify({
                  type: 'cancel_reservation',
                  reservation_id: reservationId
                }));
              }
            }
            
            function updateTables(tables) {
              const tablesDiv = document.getElementById('tables');
              tablesDiv.innerHTML = tables.map(table => \`
                <div class="table \${table.status}"
                     data-id="\${table.id}"
                     onclick="\${table.status === 'available' ? \`selectTable(\${table.id})\` : ''}">
                  <div>Mesa #\${table.id}</div>
                  <div>\${table.seats} personas</div>
                  <div>\${table.location}</div>
                  <div>\${table.status}</div>
                </div>
              \`).join('');
            }
            
            function updateReservations() {
              const reservationsDiv = document.getElementById('my-reservations');
              const myReservations = Object.values(restaurant.reservations)
                .filter(r => r.customer_id === userId);
              
              reservationsDiv.innerHTML = myReservations.map(reservation => \`
                <div class="reservation">
                  <div class="reservation-header">
                    <strong>Reserva #\${reservation.id}</strong>
                    \${reservation.status === 'pending' ? \`
                      <button onclick="cancelReservation('\${reservation.id}')">
                        Cancelar
                      </button>
                    \` : ''}
                  </div>
                  <div>Fecha: \${reservation.date}</div>
                  <div>Hora: \${reservation.time_slot}</div>
                  <div>Comensales: \${reservation.guests}</div>
                  <div>Estado: \${reservation.status}</div>
                </div>
              \`).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  restaurant = data.restaurant;
                  break;
                  
                case 'availability_result':
                  updateTables(data.tables);
                  break;
                  
                case 'table_update':
                  restaurant.tables = data.tables;
                  updateTables(data.tables);
                  break;
                  
                case 'reservation_confirmed':
                  restaurant.reservations[data.reservation.id] = data.reservation;
                  updateReservations();
                  alert('¡Reserva confirmada!');
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