require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de seguimiento de ubicación en tiempo real

class Location
  include JSON::Serializable

  property user_id : String
  property lat : Float64
  property lng : Float64
  property timestamp : String

  def initialize(@user_id : String, @lat : Float64, @lng : Float64)
    @timestamp = Time.local.to_s("%H:%M:%S")
  end
end

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      group = params["group"]?.try(&.as_s) || "default"
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, group)
      Hauyna::WebSocket::Events.send_to_group(group, {
        type:    "user_connected",
        user_id: user_id,
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if data["type"]?.try(&.as_s) == "location"
          lat = data["lat"].as_f
          lng = data["lng"].as_f
          group = data["group"]?.try(&.as_s) || "default"

          location = Location.new(user_id, lat, lng)
          Hauyna::WebSocket::Events.send_to_group(group, {
            type:     "location_update",
            location: location,
          }.to_json)
        end
      rescue ex
        socket.send({
          type:    "error",
          message: ex.message,
        }.to_json)
      end
    end
  }

  router.websocket("/track", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Rastreador de Ubicación</title>
          <link rel="stylesheet" href="https://unpkg.com/leaflet@1.7.1/dist/leaflet.css" />
          <script src="https://unpkg.com/leaflet@1.7.1/dist/leaflet.js"></script>
          <style>
            #map {
              height: 500px;
              width: 100%;
              margin: 20px 0;
            }
            .controls {
              margin: 20px;
            }
            #status {
              color: #666;
              margin: 10px 0;
            }
          </style>
        </head>
        <body>
          <div class="controls">
            <input type="text" id="groupInput" placeholder="Nombre del grupo">
            <button onclick="joinGroup()">Unirse al Grupo</button>
            <div id="status">Conectando...</div>
          </div>
          <div id="map"></div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let currentGroup = "default";
            let map;
            let markers = {};

            // Inicializar mapa
            map = L.map('map').setView([0, 0], 2);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
              attribution: '© OpenStreetMap contributors'
            }).addTo(map);

            function connectWebSocket() {
              const ws = new WebSocket(`ws://localhost:8080/track?user_id=${userId}&group=${currentGroup}`);
              
              ws.onopen = () => {
                document.getElementById('status').textContent = 'Conectado';
                startTracking();
              };

              ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                if (data.type === 'location_update') {
                  updateMarker(data.location);
                }
              };

              return ws;
            }

            let ws = connectWebSocket();

            function updateMarker(location) {
              if (markers[location.user_id]) {
                markers[location.user_id].setLatLng([location.lat, location.lng]);
              } else {
                markers[location.user_id] = L.marker([location.lat, location.lng])
                  .bindPopup(`Usuario: ${location.user_id}<br>Última actualización: ${location.timestamp}`)
                  .addTo(map);
              }
              markers[location.user_id].getPopup().setContent(
                `Usuario: ${location.user_id}<br>Última actualización: ${location.timestamp}`
              );
            }

            function startTracking() {
              if ('geolocation' in navigator) {
                navigator.geolocation.watchPosition(position => {
                  ws.send(JSON.stringify({
                    type: 'location',
                    lat: position.coords.latitude,
                    lng: position.coords.longitude,
                    group: currentGroup
                  }));
                }, error => {
                  console.error('Error:', error);
                });
              }
            }

            function joinGroup() {
              const newGroup = document.getElementById('groupInput').value.trim();
              if (newGroup) {
                currentGroup = newGroup;
                ws.close();
                ws = connectWebSocket();
                Object.values(markers).forEach(marker => map.removeLayer(marker));
                markers = {};
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
