require "../src/hauyna-web-socket"
require "http/server"

# Sistema de reserva de asientos de cine en tiempo real

class Seat
  include JSON::Serializable

  property id : String # A1, A2, B1, B2, etc.
  property row : String
  property number : Int32
  property status : String # available, reserved, occupied, disabled, pending
  property reservation_id : String?
  property user_id : String?
  property pending_user_id : String? # Usuario que está considerando el asiento

  def initialize(@row : String, @number : Int32)
    @id = "#{@row}#{@number}"
    @status = "available"
    @reservation_id = nil
    @user_id = nil
    @pending_user_id = nil
  end
end

class Screening
  include JSON::Serializable

  property id : String
  property movie : String
  property time : String
  property date : String
  property seats : Array(Seat)
  property users : Hash(String, String)               # user_id => name
  property reservations : Hash(String, Array(String)) # user_id => [seat_ids]

  def initialize(@movie : String, @time : String, @date : String)
    @id = Random::Secure.hex(8)
    @seats = [] of Seat
    @users = {} of String => String
    @reservations = {} of String => Array(String)

    # Crear sala con 8 filas (A-H) y 12 asientos por fila
    ('A'..'H').each do |row|
      (1..12).each do |number|
        seat = Seat.new(row.to_s, number)

        # Deshabilitar algunos asientos para distanciamiento
        if (row.to_s == "D" && [3, 4, 9, 10].includes?(number)) ||
           (row.to_s == "E" && [3, 4, 9, 10].includes?(number))
          seat.status = "disabled"
        end

        @seats << seat
      end
    end
  end

  def add_user(id : String, name : String)
    @users[id] = name
    @reservations[id] = [] of String
  end

  def reserve_seats(user_id : String, seat_ids : Array(String)) : Bool
    return false unless @users[user_id]?

    seats_to_reserve = @seats.select { |s| seat_ids.includes?(s.id) }
    # Solo permitir reservar asientos disponibles o pendientes por el mismo usuario
    return false if seats_to_reserve.any? { |s|
                      s.status != "available" && !(s.status == "pending" && s.pending_user_id == user_id)
                    }

    seats_to_reserve.each do |seat|
      seat.status = "reserved"
      seat.user_id = user_id
      seat.pending_user_id = nil
      @reservations[user_id] << seat.id
    end

    true
  end

  def cancel_reservation(user_id : String, seat_ids : Array(String)) : Bool
    return false unless @users[user_id]?

    seats_to_cancel = @seats.select { |s|
      seat_ids.includes?(s.id) && s.user_id == user_id
    }

    seats_to_cancel.each do |seat|
      seat.status = "available"
      seat.user_id = nil
      @reservations[user_id].delete(seat.id)
    end

    true
  end

  def mark_seats_pending(user_id : String, seat_ids : Array(String)) : Bool
    return false unless @users[user_id]?

    seats_to_mark = @seats.select { |s| seat_ids.includes?(s.id) }

    # Verificar si todos los asientos están disponibles o ya están pendientes por el mismo usuario
    return false if seats_to_mark.any? { |s|
                      s.status != "available" && !(s.status == "pending" && s.pending_user_id == user_id)
                    }

    # Si llegamos aquí, podemos marcar todos los asientos
    seats_to_mark.each do |seat|
      seat.status = "pending"
      seat.pending_user_id = user_id
    end

    true
  end

  def unmark_seats_pending(user_id : String)
    @seats.each do |seat|
      if seat.pending_user_id == user_id && seat.status == "pending"
        seat.status = "available"
        seat.pending_user_id = nil
      end
    end
  end

  def cleanup_stale_pending_seats(user_id : String)
    # Limpiar asientos pendientes antiguos del usuario
    @seats.each do |seat|
      if seat.pending_user_id == user_id && seat.status == "pending"
        seat.status = "available"
        seat.pending_user_id = nil
      end
    end
  end

  def add_to_reservation(user_id : String, seat_ids : Array(String)) : Bool
    return false unless @users[user_id]?

    seats_to_add = @seats.select { |s| seat_ids.includes?(s.id) }
    # Solo permitir agregar asientos disponibles o pendientes por el mismo usuario
    return false if seats_to_add.any? { |s|
                      s.status != "available" && !(s.status == "pending" && s.pending_user_id == user_id)
                    }

    seats_to_add.each do |seat|
      seat.status = "reserved"
      seat.user_id = user_id
      seat.pending_user_id = nil
      @reservations[user_id] << seat.id
    end

    true
  end
end

screening = Screening.new(
  "Avatar 2",
  "20:30",
  Time.local.to_s("%Y-%m-%d")
)

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        screening.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "viewers")

        socket.send({
          type:      "init",
          screening: screening,
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "mark_pending"
          seat_ids = data["seat_ids"].as_a.map(&.as_s)

          # Primero limpiar cualquier selección pendiente antigua
          screening.cleanup_stale_pending_seats(user_id)

          if screening.mark_seats_pending(user_id, seat_ids)
            Hauyna::WebSocket::Events.send_to_group("viewers", {
              type:  "seats_update",
              seats: screening.seats,
            }.to_json)
          else
            # Enviar error al cliente si no se pudo marcar
            socket.send({
              type:    "error",
              message: "No se pueden seleccionar estos asientos",
            }.to_json)
          end
        when "unmark_pending"
          seat_ids = data["seat_ids"].as_a.map(&.as_s)
          screening.unmark_seats_pending(user_id)

          Hauyna::WebSocket::Events.send_to_group("viewers", {
            type:  "seats_update",
            seats: screening.seats,
          }.to_json)
        when "reserve_seats"
          seat_ids = data["seat_ids"].as_a.map(&.as_s)

          if screening.reserve_seats(user_id, seat_ids)
            screening.unmark_seats_pending(user_id)
            Hauyna::WebSocket::Events.send_to_group("viewers", {
              type:  "seats_update",
              seats: screening.seats,
            }.to_json)
          end
        when "cancel_reservation"
          seat_ids = data["seat_ids"].as_a.map(&.as_s)

          if screening.cancel_reservation(user_id, seat_ids)
            Hauyna::WebSocket::Events.send_to_group("viewers", {
              type:  "seats_update",
              seats: screening.seats,
            }.to_json)
          end
        when "add_to_reservation"
          seat_ids = data["seat_ids"].as_a.map(&.as_s)

          if screening.add_to_reservation(user_id, seat_ids)
            screening.unmark_seats_pending(user_id)
            Hauyna::WebSocket::Events.send_to_group("viewers", {
              type:  "seats_update",
              seats: screening.seats,
            }.to_json)
          else
            socket.send({
              type:    "error",
              message: "No se pueden agregar estos asientos a tu reserva",
            }.to_json)
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

  router.websocket("/cinema", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Reserva de Asientos - Cine</title>
          <style>
            .container {
              max-width: 1000px;
              margin: 0 auto;
              padding: 20px;
            }
            .screen {
              background: #ddd;
              padding: 20px;
              text-align: center;
              border-radius: 5px;
              margin-bottom: 40px;
            }
            .seats {
              display: grid;
              grid-template-columns: repeat(12, 1fr);
              gap: 10px;
              margin: 20px 0;
            }
            .seat {
              aspect-ratio: 1;
              display: flex;
              align-items: center;
              justify-content: center;
              border-radius: 5px;
              cursor: pointer;
              font-size: 14px;
              transition: all 0.3s;
            }
            .seat.available {
              background: #4CAF50;
              color: white;
            }
            .seat.reserved {
              background: #f44336;
              color: white;
              cursor: not-allowed;
            }
            .seat.disabled {
              background: #9e9e9e;
              color: white;
              cursor: not-allowed;
            }
            .seat.selected {
              border: 3px solid #FFC107;
              box-shadow: 0 0 10px rgba(255, 193, 7, 0.5);
            }
            .seat.pending {
              background: #9e9e9e;
              color: white;
              opacity: 0.7;
              cursor: not-allowed;
            }
            .seat.pending-mine {
              background: #2196F3;
              color: white;
            }
            .legend {
              display: flex;
              gap: 20px;
              justify-content: center;
              margin: 20px 0;
            }
            .legend-item {
              display: flex;
              align-items: center;
              gap: 5px;
            }
            .legend-color {
              width: 20px;
              height: 20px;
              border-radius: 3px;
            }
            .my-reservations {
              margin-top: 40px;
            }
            .reservation {
              background: #f5f5f5;
              padding: 15px;
              border-radius: 5px;
              margin-bottom: 10px;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
            .seat:hover {
              transform: scale(1.1);
              transition: transform 0.2s;
            }
            .seat[style*="not-allowed"]:hover {
              transform: none;
            }
            .current-reservation {
              background: #f5f5f5;
              padding: 20px;
              border-radius: 5px;
              margin-top: 20px;
            }
            .cancel-all {
              margin-top: 15px;
              background: #f44336;
              color: white;
              border: none;
              padding: 10px 20px;
              border-radius: 5px;
              cursor: pointer;
            }
            .cancel-all:hover {
              background: #d32f2f;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Reserva de Asientos</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinCinema()">Entrar</button>
            </div>
            
            <div id="cinema" style="display: none;">
              <h1>Avatar 2 - 20:30</h1>
              
              <div class="screen">PANTALLA</div>
              
              <div class="legend">
                <div class="legend-item">
                  <div class="legend-color" style="background: #4CAF50"></div>
                  <span>Disponible</span>
                </div>
                <div class="legend-item">
                  <div class="legend-color" style="background: #f44336"></div>
                  <span>Reservado</span>
                </div>
                <div class="legend-item">
                  <div class="legend-color" style="background: #9e9e9e"></div>
                  <span>No disponible</span>
                </div>
                <div class="legend-item">
                  <div class="legend-color" style="background: #2196F3"></div>
                  <span>Seleccionado</span>
                </div>
                <div class="legend-item">
                  <div class="legend-color" style="background: #9e9e9e; opacity: 0.7"></div>
                  <span>Seleccionado por otro</span>
                </div>
              </div>
              
              <div id="seats" class="seats"></div>
              
              <div style="text-align: center; margin: 20px 0;">
                <button onclick="reserveSelected()" id="reserveButton">Reservar Asientos Seleccionados</button>
              </div>
              
              <div class="my-reservations">
                <h2>Mis Reservas</h2>
                <div id="reservations"></div>
              </div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let screening;
            let selectedSeats = new Set();
            let hasExistingReservation = false;
            
            function joinCinema() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('cinema').style.display = 'block';
              
              ws = new WebSocket(
                `ws://localhost:8080/cinema?user_id=${userId}&name=${name}`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function toggleSeat(seatId) {
              const seat = screening.seats.find(s => s.id === seatId);
              if (!seat) return;
              
              // No permitir interactuar con asientos reservados o deshabilitados
              if (seat.status === 'reserved' || seat.status === 'disabled') return;
              
              // No permitir seleccionar asientos pendientes de otros usuarios
              if (seat.status === 'pending' && seat.pending_user_id !== userId) {
                showError('Este asiento está siendo seleccionado por otro usuario');
                return;
              }
              
              const currentSelection = new Set(selectedSeats);
              
              if (selectedSeats.has(seatId)) {
                currentSelection.delete(seatId);
              } else {
                currentSelection.add(seatId);
              }
              
              // Enviar toda la selección actual
              ws.send(JSON.stringify({
                type: 'mark_pending',
                seat_ids: Array.from(currentSelection)
              }));
              
              selectedSeats = currentSelection;
            }
            
            function showError(message) {
              const error = document.getElementById('error');
              error.textContent = message;
              setTimeout(() => error.textContent = '', 3000);
            }
            
            function updateReserveButton() {
              const button = document.getElementById('reserveButton');
              button.textContent = hasExistingReservation ? 
                'Agregar Asientos a mi Reserva' : 
                'Reservar Asientos Seleccionados';
            }
            
            function reserveSelected() {
              if (selectedSeats.size === 0) return;
              
              const seatIds = Array.from(selectedSeats);
              ws.send(JSON.stringify({
                type: hasExistingReservation ? 'add_to_reservation' : 'reserve_seats',
                seat_ids: seatIds
              }));
            }
            
            function cancelReservation(seatIds) {
              if (confirm('¿Deseas cancelar esta reserva?')) {
                ws.send(JSON.stringify({
                  type: 'cancel_reservation',
                  seat_ids: seatIds
                }));
              }
            }
            
            function updateSeats() {
              const seatsDiv = document.getElementById('seats');
              seatsDiv.innerHTML = screening.seats.map(seat => {
                let seatClass = seat.status;
                
                // Manejar estados especiales
                if (seat.status === 'pending') {
                  if (seat.pending_user_id === userId) {
                    seatClass = 'pending-mine';
                  } else {
                    seatClass = 'pending';
                  }
                }
                
                // Agregar clase selected si está en nuestra selección
                if (selectedSeats.has(seat.id)) {
                  seatClass += ' selected';
                }
                
                let isClickable = seat.status === 'available' || 
                                (seat.status === 'pending' && seat.pending_user_id === userId) ||
                                selectedSeats.has(seat.id);
                
                return `
                  <div class="seat ${seatClass}"
                       onclick="toggleSeat('${seat.id}')"
                       style="cursor: ${isClickable ? 'pointer' : 'not-allowed'}"
                       title="${getTooltip(seat)}">
                    ${seat.id}
                  </div>
                `;
              }).join('');
            }
            
            function getTooltip(seat) {
              if (seat.status === 'reserved') return 'Asiento reservado';
              if (seat.status === 'disabled') return 'Asiento no disponible';
              if (seat.status === 'pending' && seat.pending_user_id !== userId) {
                return 'Asiento seleccionado por otro usuario';
              }
              return 'Haz clic para seleccionar';
            }
            
            function updateReservations() {
              const reservationsDiv = document.getElementById('reservations');
              const mySeats = screening.seats.filter(s => s.user_id === userId);
              
              hasExistingReservation = mySeats.length > 0;
              updateReserveButton();
              
              if (!hasExistingReservation) {
                reservationsDiv.innerHTML = '<p>No tienes reservas activas</p>';
                return;
              }
              
              const groupedByRow = mySeats.reduce((acc, seat) => {
                acc[seat.row] = acc[seat.row] || [];
                acc[seat.row].push(seat);
                return acc;
              }, {});
              
              reservationsDiv.innerHTML = `
                <div class="current-reservation">
                  ${Object.entries(groupedByRow).map(([row, seats]) => `
                    <div class="reservation">
                      <div>Fila ${row}: ${seats.map(s => s.number).join(', ')}</div>
                    </div>
                  `).join('')}
                  <button onclick='cancelReservation(${JSON.stringify(mySeats.map(s => s.id))})' 
                          class="cancel-all">
                    Cancelar Toda la Reserva
                  </button>
                </div>
              `;
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  screening = data.screening;
                  updateSeats();
                  updateReservations();
                  break;
                  
                case 'seats_update':
                  screening.seats = data.seats;
                  selectedSeats = new Set(
                    Array.from(selectedSeats).filter(seatId => {
                      const seat = screening.seats.find(s => s.id === seatId);
                      return seat && (
                        seat.status === "available" || 
                        (seat.status === "pending" && seat.pending_user_id === userId) ||
                        (seat.status === "reserved" && seat.user_id === userId)
                      );
                    })
                  );
                  updateSeats();
                  updateReservations();
                  break;
                  
                case 'error':
                  showError(data.message);
                  // Actualizar la UI para reflejar el estado actual
                  updateSeats();
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
