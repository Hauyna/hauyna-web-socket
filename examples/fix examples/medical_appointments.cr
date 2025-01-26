require "../src/hauyna-web-socket"
require "http/server"

# Sistema de reservas de citas médicas en tiempo real

class Doctor
  include JSON::Serializable

  property id : String
  property name : String
  property specialty : String
  property schedule : Array(TimeSlot)
  property status : String # available, busy, off

  def initialize(@name : String, @specialty : String)
    @id = Random::Secure.hex(8)
    @schedule = [] of TimeSlot
    @status = "available"
    generate_schedule
  end

  private def generate_schedule
    # Generar horarios para la próxima semana
    7.times do |day|
      # Horario de 9:00 a 17:00
      (9..16).each do |hour|
        @schedule << TimeSlot.new(
          Time.local.at_beginning_of_day + day.days + hour.hours,
          30 # duración en minutos
        )
      end
    end
  end
end

class TimeSlot
  include JSON::Serializable

  property id : String
  property start_time : Time
  property duration : Int32 # minutos
  property status : String  # available, booked, past
  property appointment_id : String?

  def initialize(@start_time : Time, @duration : Int32)
    @id = Random::Secure.hex(8)
    @status = "available"
    @appointment_id = nil
  end

  def end_time : Time
    @start_time + @duration.minutes
  end

  def update_status
    if Time.local > end_time
      @status = "past"
    end
  end
end

class Appointment
  include JSON::Serializable

  property id : String
  property doctor_id : String
  property patient_id : String
  property patient_name : String
  property time_slot_id : String
  property reason : String
  property status : String # confirmed, cancelled, completed
  property created_at : Time

  def initialize(@doctor_id : String, @patient_id : String, @patient_name : String, @time_slot_id : String, @reason : String)
    @id = Random::Secure.hex(8)
    @status = "confirmed"
    @created_at = Time.local
  end
end

class MedicalSystem
  include JSON::Serializable

  property doctors : Hash(String, Doctor)
  property appointments : Hash(String, Appointment)
  property users : Hash(String, String) # user_id => name
  property notifications : Array(String)

  def initialize
    @doctors = {} of String => Doctor
    @appointments = {} of String => Appointment
    @users = {} of String => String
    @notifications = [] of String

    setup_demo_doctors
  end

  def add_user(id : String, name : String)
    @users[id] = name
  end

  def book_appointment(doctor_id : String, time_slot_id : String, patient_id : String, reason : String) : Bool
    if doctor = @doctors[doctor_id]?
      if time_slot = doctor.schedule.find { |ts| ts.id == time_slot_id }
        return false if time_slot.status != "available"

        appointment = Appointment.new(
          doctor_id: doctor_id,
          patient_id: patient_id,
          patient_name: @users[patient_id],
          time_slot_id: time_slot_id,
          reason: reason
        )

        time_slot.status = "booked"
        time_slot.appointment_id = appointment.id
        @appointments[appointment.id] = appointment

        add_notification("Nueva cita: #{@users[patient_id]} con #{doctor.name} para #{time_slot.start_time.to_s("%d/%m/%Y %H:%M")}")
        true
      else
        false
      end
    else
      false
    end
  end

  def cancel_appointment(appointment_id : String, user_id : String) : Bool
    if appointment = @appointments[appointment_id]?
      return false unless appointment.patient_id == user_id
      return false if appointment.status != "confirmed"

      if doctor = @doctors[appointment.doctor_id]?
        if time_slot = doctor.schedule.find { |ts| ts.id == appointment.time_slot_id }
          time_slot.status = "available"
          time_slot.appointment_id = nil
          appointment.status = "cancelled"

          add_notification("Cita cancelada: #{appointment.patient_name} con #{doctor.name} para #{time_slot.start_time.to_s("%d/%m/%Y %H:%M")}")
          true
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end

  private def add_notification(message : String)
    @notifications << "[#{Time.local}] #{message}"
    @notifications = @notifications.last(50)
  end

  private def setup_demo_doctors
    [
      {name: "Dr. García", specialty: "Medicina General"},
      {name: "Dra. Rodríguez", specialty: "Pediatría"},
      {name: "Dr. López", specialty: "Cardiología"},
    ].each do |d|
      doctor = Doctor.new(d[:name], d[:specialty])
      @doctors[doctor.id] = doctor
    end
  end
end

system = MedicalSystem.new

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
          type:   "init",
          system: system,
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "book_appointment"
          if system.book_appointment(
               data["doctor_id"].as_s,
               data["time_slot_id"].as_s,
               user_id,
               data["reason"].as_s
             )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type:   "system_update",
              system: system,
            }.to_json)
          end
        when "cancel_appointment"
          if system.cancel_appointment(
               data["appointment_id"].as_s,
               user_id
             )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type:   "system_update",
              system: system,
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

  # Actualizar estados de time slots periódicamente
  spawn do
    loop do
      sleep 1.minute

      system.doctors.each_value do |doctor|
        doctor.schedule.each(&.update_status)
      end

      Hauyna::WebSocket::Events.send_to_group("users", {
        type:   "system_update",
        system: system,
      }.to_json)
    end
  end

  router.websocket("/medical", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Citas Médicas</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .doctors {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin: 20px 0;
            }
            .doctor-card {
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .schedule {
              display: grid;
              grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
              gap: 10px;
              margin-top: 15px;
            }
            .time-slot {
              padding: 10px;
              border-radius: 4px;
              cursor: pointer;
              text-align: center;
            }
            .available {
              background: #c8e6c9;
              color: #2e7d32;
            }
            .booked {
              background: #ffcdd2;
              color: #c62828;
            }
            .past {
              background: #f5f5f5;
              color: #9e9e9e;
              cursor: not-allowed;
            }
            .appointments {
              margin: 20px 0;
            }
            .appointment {
              background: white;
              padding: 15px;
              margin: 10px 0;
              border-radius: 4px;
              box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            }
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
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Sistema de Citas Médicas</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinSystem()">Entrar</button>
            </div>
            
            <div id="medical-system" style="display: none;">
              <h1>Citas Médicas</h1>
              
              <div class="notifications">
                <h2>Notificaciones</h2>
                <div id="notifications"></div>
              </div>
              
              <h2>Doctores Disponibles</h2>
              <div id="doctors" class="doctors"></div>
              
              <h2>Mis Citas</h2>
              <div id="my-appointments" class="appointments"></div>
            </div>
          </div>
          
          <div id="booking-modal" class="modal">
            <div class="modal-content">
              <h2>Reservar Cita</h2>
              <p id="booking-info"></p>
              <div>
                <label>Motivo de la consulta:</label>
                <textarea id="reason" rows="3"></textarea>
              </div>
              <button onclick="confirmBooking()">Confirmar</button>
              <button onclick="closeModal()">Cancelar</button>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let system;
            let selectedSlot = null;
            let selectedDoctor = null;
            
            function joinSystem() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('medical-system').style.display = 'block';
              
              ws = new WebSocket(
                `ws://localhost:8080/medical?user_id=${userId}&name=${name}`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function openBookingModal(doctorId, timeSlotId) {
              const doctor = system.doctors[doctorId];
              const timeSlot = doctor.schedule.find(ts => ts.id === timeSlotId);
              
              if (timeSlot.status !== 'available') return;
              
              selectedDoctor = doctorId;
              selectedSlot = timeSlotId;
              
              document.getElementById('booking-info').textContent = 
                `${doctor.name} - ${new Date(timeSlot.start_time).toLocaleString()}`;
              document.getElementById('booking-modal').style.display = 'block';
            }
            
            function closeModal() {
              document.getElementById('booking-modal').style.display = 'none';
              selectedDoctor = null;
              selectedSlot = null;
            }
            
            function confirmBooking() {
              const reason = document.getElementById('reason').value.trim();
              if (!reason) return;
              
              ws.send(JSON.stringify({
                type: 'book_appointment',
                doctor_id: selectedDoctor,
                time_slot_id: selectedSlot,
                reason: reason
              }));
              
              closeModal();
            }
            
            function cancelAppointment(appointmentId) {
              if (confirm('¿Deseas cancelar esta cita?')) {
                ws.send(JSON.stringify({
                  type: 'cancel_appointment',
                  appointment_id: appointmentId
                }));
              }
            }
            
            function updateUI() {
              // Actualizar doctores y horarios
              const doctorsDiv = document.getElementById('doctors');
              doctorsDiv.innerHTML = Object.values(system.doctors)
                .map(doctor => `
                  <div class="doctor-card">
                    <h3>${doctor.name}</h3>
                    <div>${doctor.specialty}</div>
                    <div class="schedule">
                      ${doctor.schedule
                        .filter(ts => ts.status !== 'past')
                        .map(timeSlot => `
                          <div class="time-slot ${timeSlot.status}"
                               onclick="openBookingModal('${doctor.id}', '${timeSlot.id}')">
                            ${new Date(timeSlot.start_time).toLocaleString()}
                          </div>
                        `).join('')}
                    </div>
                  </div>
                `).join('');
              
              // Actualizar mis citas
              const appointmentsDiv = document.getElementById('my-appointments');
              const myAppointments = Object.values(system.appointments)
                .filter(a => a.patient_id === userId && a.status === 'confirmed');
              
              appointmentsDiv.innerHTML = myAppointments
                .map(appointment => {
                  const doctor = system.doctors[appointment.doctor_id];
                  const timeSlot = doctor.schedule.find(ts => ts.id === appointment.time_slot_id);
                  return `
                    <div class="appointment">
                      <div>Doctor: ${doctor.name}</div>
                      <div>Fecha: ${new Date(timeSlot.start_time).toLocaleString()}</div>
                      <div>Motivo: ${appointment.reason}</div>
                      <button onclick="cancelAppointment('${appointment.id}')">
                        Cancelar
                      </button>
                    </div>
                  `;
                }).join('');
              
              // Actualizar notificaciones
              const notificationsDiv = document.getElementById('notifications');
              notificationsDiv.innerHTML = system.notifications
                .slice().reverse()
                .map(notification => `
                  <div class="notification">${notification}</div>
                `).join('');
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
