require "../src/hauyna-web-socket"
require "http/server"

# Sistema de monitoreo de sensores IoT en tiempo real

class Sensor
  include JSON::Serializable
  
  property id : String
  property name : String
  property type : String # temperature, humidity, pressure, co2, light
  property location : String
  property value : Float64
  property unit : String
  property status : String # normal, warning, alert
  property last_reading : Time
  property thresholds : Thresholds
  
  def initialize(@name : String, @type : String, @location : String, @thresholds : Thresholds)
    @id = Random::Secure.hex(8)
    @value = 0.0
    @unit = get_unit
    @status = "normal"
    @last_reading = Time.local
  end
  
  def update_reading(value : Float64)
    @value = value
    @last_reading = Time.local
    @status = calculate_status
  end
  
  def calculate_status : String
    case @type
    when "temperature"
      if @value > @thresholds.critical_high || @value < @thresholds.critical_low
        "alert"
      elsif @value > @thresholds.warning_high || @value < @thresholds.warning_low
        "warning"
      else
        "normal"
      end
    when "humidity"
      if @value > 80 || @value < 20
        "alert"
      elsif @value > 70 || @value < 30
        "warning"
      else
        "normal"
      end
    when "co2"
      if @value > 2000
        "alert"
      elsif @value > 1000
        "warning"
      else
        "normal"
      end
    else
      "normal"
    end
  end
  
  private def get_unit : String
    case @type
    when "temperature" then "°C"
    when "humidity" then "%"
    when "pressure" then "hPa"
    when "co2" then "ppm"
    when "light" then "lux"
    else "unknown"
    end
  end
end

class Thresholds
  include JSON::Serializable
  
  property warning_low : Float64
  property warning_high : Float64
  property critical_low : Float64
  property critical_high : Float64
  
  def initialize(@warning_low : Float64, @warning_high : Float64, @critical_low : Float64, @critical_high : Float64)
  end
end

class Reading
  include JSON::Serializable
  
  property sensor_id : String
  property value : Float64
  property timestamp : Time
  
  def initialize(@sensor_id : String, @value : Float64)
    @timestamp = Time.local
  end
end

class IoTSystem
  include JSON::Serializable
  
  property sensors : Hash(String, Sensor)
  property readings : Array(Reading)
  property alerts : Array(String)
  property users : Hash(String, String)
  
  def initialize
    @sensors = {} of String => Sensor
    @readings = [] of Reading
    @alerts = [] of String
    @users = {} of String => String
    
    setup_demo_sensors
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
  
  def add_reading(sensor_id : String, value : Float64)
    if sensor = @sensors[sensor_id]?
      old_status = sensor.status
      sensor.update_reading(value)
      
      reading = Reading.new(sensor_id, value)
      @readings << reading
      @readings = @readings.last(1000) # Mantener últimas 1000 lecturas
      
      if old_status != sensor.status
        add_alert("#{sensor.name} en #{sensor.location}: #{sensor.status.upcase} (#{sensor.value}#{sensor.unit})")
      end
      
      true
    else
      false
    end
  end
  
  private def add_alert(message : String)
    @alerts << "[#{Time.local}] #{message}"
    @alerts = @alerts.last(50)
  end
  
  private def setup_demo_sensors
    [
      {
        name: "Sensor Temperatura 1",
        type: "temperature",
        location: "Sala de Servidores",
        thresholds: Thresholds.new(18.0, 25.0, 15.0, 28.0)
      },
      {
        name: "Sensor Humedad 1",
        type: "humidity",
        location: "Sala de Servidores",
        thresholds: Thresholds.new(30.0, 70.0, 20.0, 80.0)
      },
      {
        name: "Sensor CO2",
        type: "co2",
        location: "Oficina Principal",
        thresholds: Thresholds.new(600.0, 1000.0, 800.0, 2000.0)
      }
    ].each do |s|
      sensor = Sensor.new(
        name: s[:name],
        type: s[:type],
        location: s[:location],
        thresholds: s[:thresholds]
      )
      @sensors[sensor.id] = sensor
    end
  end
end

system = IoTSystem.new

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

  # Simulación de lecturas de sensores
  spawn do
    loop do
      sleep 2.seconds
      
      system.sensors.each do |id, sensor|
        # Simular lecturas con variación aleatoria
        base_value = case sensor.type
        when "temperature" then 22.0
        when "humidity" then 50.0
        when "co2" then 800.0
        else 0.0
        end
        
        variation = (rand - 0.5) * 10
        new_value = base_value + variation
        
        if system.add_reading(id, new_value)
          Hauyna::WebSocket::Events.send_to_group("users", {
            type: "system_update",
            system: system
          }.to_json)
        end
      end
    end
  end

  router.websocket("/iot", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Monitoreo IoT</title>
          <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
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
            .sensor-card {
              background: white;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .sensor-header {
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 15px;
            }
            .sensor-value {
              font-size: 24px;
              font-weight: bold;
            }
            .status-normal { color: #2e7d32; }
            .status-warning { color: #f57f17; }
            .status-alert { color: #c62828; }
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
            .chart-container {
              position: relative;
              height: 200px;
              margin-top: 10px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Sistema de Monitoreo IoT</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinSystem()">Entrar</button>
            </div>
            
            <div id="iot-system" style="display: none;">
              <h1>Monitoreo de Sensores</h1>
              
              <div class="alerts">
                <h2>Alertas</h2>
                <div id="alerts"></div>
              </div>
              
              <div id="sensors" class="grid"></div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let system;
            let charts = {};
            
            function joinSystem() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('iot-system').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/iot?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function createChart(ctx, label) {
              return new Chart(ctx, {
                type: 'line',
                data: {
                  labels: [],
                  datasets: [{
                    label: label,
                    data: [],
                    borderColor: '#2196f3',
                    tension: 0.4
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  scales: {
                    y: {
                      beginAtZero: true
                    }
                  },
                  animation: false
                }
              });
            }
            
            function updateUI() {
              // Actualizar sensores
              const sensorsDiv = document.getElementById('sensors');
              sensorsDiv.innerHTML = Object.values(system.sensors)
                .map(sensor => \`
                  <div class="sensor-card">
                    <div class="sensor-header">
                      <h3>\${sensor.name}</h3>
                      <div class="sensor-value status-\${sensor.status}">
                        \${sensor.value.toFixed(1)}\${sensor.unit}
                      </div>
                    </div>
                    <div>Ubicación: \${sensor.location}</div>
                    <div>Estado: \${sensor.status.toUpperCase()}</div>
                    <div>Última lectura: \${new Date(sensor.last_reading).toLocaleTimeString()}</div>
                    <div class="chart-container">
                      <canvas id="chart-\${sensor.id}"></canvas>
                    </div>
                  </div>
                \`).join('');
              
              // Inicializar o actualizar gráficos
              Object.values(system.sensors).forEach(sensor => {
                const ctx = document.getElementById(\`chart-\${sensor.id}\`);
                if (!charts[sensor.id]) {
                  charts[sensor.id] = createChart(ctx, sensor.name);
                }
                
                const readings = system.readings
                  .filter(r => r.sensor_id === sensor.id)
                  .slice(-20);
                
                charts[sensor.id].data.labels = readings.map(r => 
                  new Date(r.timestamp).toLocaleTimeString()
                );
                charts[sensor.id].data.datasets[0].data = readings.map(r => r.value);
                charts[sensor.id].update();
              });
              
              // Actualizar alertas
              const alertsDiv = document.getElementById('alerts');
              alertsDiv.innerHTML = system.alerts
                .slice().reverse()
                .map(alert => \`
                  <div class="alert">\${alert}</div>
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