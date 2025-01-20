require "../src/hauyna-web-socket"
require "http/server"

# Sistema de control domótico en tiempo real

class Device
  include JSON::Serializable
  
  property id : String
  property name : String
  property type : String # light, thermostat, camera, lock, sensor
  property status : String # on/off, temperature, motion, locked/unlocked
  property value : Float64? # para temperatura, brillo, etc
  property room : String
  property last_update : Time
  
  def initialize(@name : String, @type : String, @room : String)
    @id = Random::Secure.hex(8)
    @status = default_status
    @value = default_value
    @last_update = Time.local
  end
  
  private def default_status : String
    case @type
    when "light" then "off"
    when "thermostat" then "off"
    when "camera" then "off"
    when "lock" then "locked"
    when "sensor" then "no-motion"
    else "unknown"
    end
  end
  
  private def default_value : Float64?
    case @type
    when "thermostat" then 21.0
    when "light" then 0.0
    else nil
    end
  end
end

class Scene
  include JSON::Serializable
  
  property id : String
  property name : String
  property actions : Array(SceneAction)
  
  def initialize(@name : String, @actions : Array(SceneAction))
    @id = Random::Secure.hex(8)
  end
end

class SceneAction
  include JSON::Serializable
  
  property device_id : String
  property status : String
  property value : Float64?
  
  def initialize(@device_id : String, @status : String, @value : Float64? = nil)
  end
end

class SmartHome
  include JSON::Serializable
  
  property devices : Hash(String, Device)
  property scenes : Hash(String, Scene)
  property users : Hash(String, String) # user_id => name
  property activity_log : Array(String)
  
  def initialize
    @devices = {} of String => Device
    @scenes = {} of String => Scene
    @users = {} of String => String
    @activity_log = [] of String
    
    setup_demo_devices
    setup_demo_scenes
  end
  
  def add_user(id : String, name : String)
    @users[id] = name
  end
  
  def update_device(device_id : String, status : String, value : Float64? = nil) : Bool
    if device = @devices[device_id]?
      old_status = device.status
      old_value = device.value
      
      device.status = status
      device.value = value
      device.last_update = Time.local
      
      log_activity("#{device.name} en #{device.room}: #{old_status} -> #{status}")
      true
    else
      false
    end
  end
  
  def activate_scene(scene_id : String) : Bool
    if scene = @scenes[scene_id]?
      scene.actions.each do |action|
        update_device(action.device_id, action.status, action.value)
      end
      
      log_activity("Escena activada: #{scene.name}")
      true
    else
      false
    end
  end
  
  private def setup_demo_devices
    # Luces
    add_device(Device.new("Luz Principal", "light", "Sala"))
    add_device(Device.new("Luz Ambiente", "light", "Sala"))
    add_device(Device.new("Luz Escritorio", "light", "Oficina"))
    
    # Termostatos
    add_device(Device.new("Termostato", "thermostat", "Sala"))
    add_device(Device.new("Termostato", "thermostat", "Dormitorio"))
    
    # Cámaras
    add_device(Device.new("Cámara Entrada", "camera", "Entrada"))
    add_device(Device.new("Cámara Patio", "camera", "Patio"))
    
    # Cerraduras
    add_device(Device.new("Cerradura Principal", "lock", "Entrada"))
    add_device(Device.new("Cerradura Garaje", "lock", "Garaje"))
    
    # Sensores
    add_device(Device.new("Sensor Movimiento", "sensor", "Entrada"))
    add_device(Device.new("Sensor Movimiento", "sensor", "Patio"))
  end
  
  private def setup_demo_scenes
    # Escena: Llegada a casa
    @scenes["arrival"] = Scene.new("Llegada a Casa", [
      SceneAction.new(@devices.values.find { |d| d.name == "Luz Principal" }.not_nil!.id, "on", 100.0),
      SceneAction.new(@devices.values.find { |d| d.name == "Termostato" && d.room == "Sala" }.not_nil!.id, "on", 22.0),
      SceneAction.new(@devices.values.find { |d| d.name == "Cerradura Principal" }.not_nil!.id, "unlocked")
    ])
    
    # Escena: Salida de casa
    @scenes["departure"] = Scene.new("Salida de Casa", [
      SceneAction.new(@devices.values.find { |d| d.type == "light" }.not_nil!.id, "off"),
      SceneAction.new(@devices.values.find { |d| d.type == "thermostat" }.not_nil!.id, "off"),
      SceneAction.new(@devices.values.find { |d| d.type == "lock" }.not_nil!.id, "locked"),
      SceneAction.new(@devices.values.find { |d| d.type == "camera" }.not_nil!.id, "on")
    ])
    
    # Escena: Modo Noche
    @scenes["night"] = Scene.new("Modo Noche", [
      SceneAction.new(@devices.values.find { |d| d.name == "Luz Ambiente" }.not_nil!.id, "on", 30.0),
      SceneAction.new(@devices.values.find { |d| d.type == "thermostat" }.not_nil!.id, "on", 20.0),
      SceneAction.new(@devices.values.find { |d| d.type == "lock" }.not_nil!.id, "locked"),
      SceneAction.new(@devices.values.find { |d| d.type == "camera" }.not_nil!.id, "on")
    ])
  end
  
  private def add_device(device : Device)
    @devices[device.id] = device
  end
  
  private def log_activity(message : String)
    @activity_log << "[#{Time.local}] #{message}"
    @activity_log = @activity_log.last(50) # Mantener solo las últimas 50 actividades
  end
end

home = SmartHome.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        home.add_user(user_id, name)
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
        
        socket.send({
          type: "init",
          home: home
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "update_device"
          value = if v = data["value"]?
            v.as_f?
          end
          
          if home.update_device(
            data["device_id"].as_s,
            data["status"].as_s,
            value
          )
            Hauyna::WebSocket::Events.send_to_group("users", {
              type: "home_update",
              home: home
            }.to_json)
          end
          
        when "activate_scene"
          if home.activate_scene(data["scene_id"].as_s)
            Hauyna::WebSocket::Events.send_to_group("users", {
              type: "home_update",
              home: home
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

  # Simulación de eventos de sensores
  spawn do
    loop do
      sleep rand(5..15).seconds
      
      # Simular detección de movimiento aleatoria
      sensors = home.devices.values.select { |d| d.type == "sensor" }
      if sensor = sensors.sample
        home.update_device(
          sensor.id,
          ["motion", "no-motion"].sample,
          nil
        )
        
        Hauyna::WebSocket::Events.send_to_group("users", {
          type: "home_update",
          home: home
        }.to_json)
      end
    end
  end

  router.websocket("/smart-home", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Control Domótico</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .rooms {
              display: grid;
              grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 20px;
              margin: 20px 0;
            }
            .room {
              background: #f5f5f5;
              padding: 20px;
              border-radius: 8px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .device {
              background: white;
              padding: 15px;
              margin: 10px 0;
              border-radius: 4px;
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            .device-controls {
              display: flex;
              gap: 10px;
              align-items: center;
            }
            .scenes {
              margin: 20px 0;
            }
            .scene {
              background: #e3f2fd;
              padding: 15px;
              margin: 10px 0;
              border-radius: 4px;
              cursor: pointer;
              transition: all 0.3s;
            }
            .scene:hover {
              background: #bbdefb;
            }
            .activity-log {
              margin-top: 20px;
              padding: 20px;
              background: #f8f9fa;
              border-radius: 8px;
              max-height: 300px;
              overflow-y: auto;
            }
            .log-entry {
              padding: 5px 0;
              border-bottom: 1px solid #eee;
            }
            .status-on {
              color: #4CAF50;
            }
            .status-off {
              color: #f44336;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Control Domótico</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinHome()">Entrar</button>
            </div>
            
            <div id="smart-home" style="display: none;">
              <h1>Control Domótico</h1>
              
              <div class="scenes">
                <h2>Escenas</h2>
                <div id="scenes"></div>
              </div>
              
              <div class="rooms" id="rooms"></div>
              
              <div class="activity-log">
                <h2>Actividad Reciente</h2>
                <div id="activity-log"></div>
              </div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let home;
            
            function joinHome() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('smart-home').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/smart-home?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function updateDevice(deviceId, status, value = null) {
              const data = {
                type: 'update_device',
                device_id: deviceId,
                status: status
              };
              
              if (value !== null) {
                data.value = parseFloat(value);
              }
              
              ws.send(JSON.stringify(data));
            }
            
            function activateScene(sceneId) {
              ws.send(JSON.stringify({
                type: 'activate_scene',
                scene_id: sceneId
              }));
            }
            
            function getDeviceControls(device) {
              switch(device.type) {
                case 'light':
                  return \`
                    <div class="device-controls">
                      <button onclick="updateDevice('\${device.id}', '\${device.status === 'on' ? 'off' : 'on'}')">
                        \${device.status === 'on' ? 'Apagar' : 'Encender'}
                      </button>
                      \${device.status === 'on' ? \`
                        <input type="range" min="0" max="100" value="\${device.value || 0}"
                               onchange="updateDevice('\${device.id}', 'on', this.value)">
                      \` : ''}
                    </div>
                  \`;
                  
                case 'thermostat':
                  return \`
                    <div class="device-controls">
                      <button onclick="updateDevice('\${device.id}', '\${device.status === 'on' ? 'off' : 'on'}')">
                        \${device.status === 'on' ? 'Apagar' : 'Encender'}
                      </button>
                      \${device.status === 'on' ? \`
                        <input type="number" min="16" max="30" value="\${device.value || 21}"
                               onchange="updateDevice('\${device.id}', 'on', this.value)">°C
                      \` : ''}
                    </div>
                  \`;
                  
                case 'lock':
                  return \`
                    <button onclick="updateDevice('\${device.id}', '\${device.status === 'locked' ? 'unlocked' : 'locked'}')">
                      \${device.status === 'locked' ? 'Desbloquear' : 'Bloquear'}
                    </button>
                  \`;
                  
                case 'camera':
                  return \`
                    <button onclick="updateDevice('\${device.id}', '\${device.status === 'on' ? 'off' : 'on'}')">
                      \${device.status === 'on' ? 'Apagar' : 'Encender'}
                    </button>
                  \`;
                  
                default:
                  return '';
              }
            }
            
            function updateUI() {
              // Actualizar escenas
              const scenesDiv = document.getElementById('scenes');
              scenesDiv.innerHTML = Object.values(home.scenes)
                .map(scene => \`
                  <div class="scene" onclick="activateScene('\${scene.id}')">
                    <h3>\${scene.name}</h3>
                  </div>
                \`).join('');
              
              // Agrupar dispositivos por habitación
              const rooms = {};
              Object.values(home.devices).forEach(device => {
                rooms[device.room] = rooms[device.room] || [];
                rooms[device.room].push(device);
              });
              
              // Actualizar dispositivos por habitación
              const roomsDiv = document.getElementById('rooms');
              roomsDiv.innerHTML = Object.entries(rooms)
                .map(([room, devices]) => \`
                  <div class="room">
                    <h2>\${room}</h2>
                    \${devices.map(device => \`
                      <div class="device">
                        <div>
                          <div>\${device.name}</div>
                          <div class="status-\${device.status === 'on' ? 'on' : 'off'}">
                            \${device.status}
                            \${device.value ? \` (\${device.value}\${device.type === 'thermostat' ? '°C' : '%'})\` : ''}
                          </div>
                        </div>
                        \${getDeviceControls(device)}
                      </div>
                    \`).join('')}
                  </div>
                \`).join('');
              
              // Actualizar log de actividad
              const logDiv = document.getElementById('activity-log');
              logDiv.innerHTML = home.activity_log
                .reverse()
                .map(entry => \`
                  <div class="log-entry">\${entry}</div>
                \`).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                case 'home_update':
                  home = data.home;
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