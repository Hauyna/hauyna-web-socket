require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de música sincronizada

class Track
  include JSON::Serializable

  property id : String
  property title : String
  property artist : String
  property url : String
  property duration : Int32

  def initialize(@id, @title, @artist, @url, @duration)
  end
end

class Room
  include JSON::Serializable

  property playlist : Array(Track)
  property current_track : Int32
  property is_playing : Bool
  property current_time : Float64
  property last_update : Time
  property listeners : Set(String)

  def initialize
    @playlist = [] of Track
    @current_track = 0
    @is_playing = false
    @current_time = 0.0
    @last_update = Time.local
    @listeners = Set(String).new
  end

  def add_track(track : Track)
    @playlist << track
  end

  def play
    @is_playing = true
    @last_update = Time.local
  end

  def pause
    @is_playing = false
    @last_update = Time.local
  end

  def next_track
    @current_track = (@current_track + 1) % @playlist.size
    @current_time = 0.0
    @last_update = Time.local
  end

  def current_position : Float64
    if @is_playing
      @current_time + (Time.local - @last_update).total_seconds
    else
      @current_time
    end
  end
end

# Crear sala con algunas canciones de ejemplo
room = Room.new
room.add_track(Track.new(
  "1",
  "Ejemplo 1",
  "Artista 1",
  "https://example.com/song1.mp3",
  180
))
room.add_track(Track.new(
  "2",
  "Ejemplo 2",
  "Artista 2",
  "https://example.com/song2.mp3",
  240
))

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["listener_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if listener_id = params["listener_id"]?.try(&.as_s)
      room.listeners.add(listener_id)
      Hauyna::WebSocket::ConnectionManager.add_to_group(listener_id, "listeners")

      socket.send({
        type: "init",
        room: room,
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if listener_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["action"]?.try(&.as_s)
        when "play"
          room.play
        when "pause"
          room.pause
        when "next"
          room.next_track
        when "seek"
          if time = data["time"]?.try(&.as_f)
            room.current_time = time
            room.last_update = Time.local
          end
        end

        Hauyna::WebSocket::Events.send_to_group("listeners", {
          type: "room_update",
          room: room,
        }.to_json)
      rescue ex
        socket.send({
          type:    "error",
          message: ex.message,
        }.to_json)
      end
    end
  }

  # Enviar actualizaciones periódicas del tiempo
  spawn do
    loop do
      sleep 1.seconds
      if room.is_playing
        current_position = room.current_position
        current_track = room.playlist[room.current_track]

        if current_position >= current_track.duration
          room.next_track
        end

        Hauyna::WebSocket::Events.send_to_group("listeners", {
          type:     "time_update",
          position: room.current_position,
        }.to_json)
      end
    end
  end

  router.websocket("/music", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Música Sincronizada</title>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .player {
              border: 1px solid #ccc;
              padding: 20px;
              border-radius: 8px;
            }
            .controls {
              display: flex;
              gap: 10px;
              margin: 20px 0;
            }
            .progress {
              width: 100%;
              height: 20px;
              background: #f0f0f0;
              border-radius: 10px;
              overflow: hidden;
              cursor: pointer;
            }
            .progress-bar {
              height: 100%;
              background: #4CAF50;
              width: 0%;
              transition: width 0.1s linear;
            }
            .track-info {
              margin: 10px 0;
            }
            .playlist {
              margin-top: 20px;
            }
            .track {
              padding: 10px;
              border-bottom: 1px solid #eee;
              cursor: pointer;
            }
            .track:hover {
              background: #f5f5f5;
            }
            .track.current {
              background: #e3f2fd;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="player">
              <div class="track-info">
                <h2 id="title"></h2>
                <div id="artist"></div>
              </div>
              <div class="progress" id="progress">
                <div class="progress-bar" id="progress-bar"></div>
              </div>
              <div class="controls">
                <button onclick="togglePlay()">Play/Pause</button>
                <button onclick="nextTrack()">Siguiente</button>
                <span id="time"></span>
              </div>
            </div>
            <div class="playlist" id="playlist"></div>
          </div>

          <script>
            const listenerId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(`ws://localhost:8080/music?listener_id=${listenerId}`);
            let room;
            
            function formatTime(seconds) {
              const mins = Math.floor(seconds / 60);
              const secs = Math.floor(seconds % 60);
              return `${mins}:${secs.toString().padStart(2, '0')}`;
            }

            function updatePlayer() {
              if (!room) return;
              
              const track = room.playlist[room.current_track];
              document.getElementById('title').textContent = track.title;
              document.getElementById('artist').textContent = track.artist;
              
              const playlist = document.getElementById('playlist');
              playlist.innerHTML = room.playlist
                .map((track, index) => `
                  <div class="track ${index === room.current_track ? 'current' : ''}">
                    ${track.title} - ${track.artist}
                  </div>
                `).join('');
            }

            function updateProgress(position) {
              const track = room.playlist[room.current_track];
              const progress = (position / track.duration) * 100;
              document.getElementById('progress-bar').style.width = `${progress}%`;
              document.getElementById('time').textContent = 
                `${formatTime(position)} / ${formatTime(track.duration)}`;
            }

            function togglePlay() {
              ws.send(JSON.stringify({
                action: room.is_playing ? 'pause' : 'play'
              }));
            }

            function nextTrack() {
              ws.send(JSON.stringify({
                action: 'next'
              }));
            }

            document.getElementById('progress').onclick = (e) => {
              const rect = e.target.getBoundingClientRect();
              const x = e.clientX - rect.left;
              const width = rect.width;
              const track = room.playlist[room.current_track];
              const time = (x / width) * track.duration;
              
              ws.send(JSON.stringify({
                action: 'seek',
                time: time
              }));
            };

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  room = data.room;
                  updatePlayer();
                  break;
                  
                case 'room_update':
                  room = data.room;
                  updatePlayer();
                  break;
                  
                case 'time_update':
                  updateProgress(data.position);
                  break;
                  
                case 'error':
                  console.error(data.message);
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
