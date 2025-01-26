require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de sistema de presentaciones en tiempo real

class Presentation
  include JSON::Serializable

  property slides : Array(String)
  property current_slide : Int32
  property presenter_id : String?
  property viewers : Set(String)

  def initialize(@slides : Array(String))
    @current_slide = 0
    @presenter_id = nil
    @viewers = Set(String).new
  end

  def next_slide : Bool
    return false if @current_slide >= @slides.size - 1
    @current_slide += 1
    true
  end

  def previous_slide : Bool
    return false if @current_slide <= 0
    @current_slide -= 1
    true
  end
end

# Crear una presentación de ejemplo
presentation = Presentation.new([
  "# Bienvenidos\n\nPresentación en tiempo real con Crystal",
  "## Características\n\n- Sincronización en tiempo real\n- Control de presentador\n- Markdown support",
  "## Ejemplo de código\n\n```crystal\nputs \"Hello World!\"\n```",
  "# ¡Gracias!\n\n¿Preguntas?",
])

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      presentation.viewers.add(user_id)

      # El primer usuario se convierte en presentador
      presentation.presenter_id = user_id if presentation.presenter_id.nil?

      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "viewers")
      socket.send({
        type:         "init",
        presentation: presentation,
        is_presenter: user_id == presentation.presenter_id,
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if user_id == presentation.presenter_id
          case data["action"]?.try(&.as_s)
          when "next"
            if presentation.next_slide
              Hauyna::WebSocket::Events.send_to_group("viewers", {
                type:  "slide_change",
                slide: presentation.current_slide,
              }.to_json)
            end
          when "previous"
            if presentation.previous_slide
              Hauyna::WebSocket::Events.send_to_group("viewers", {
                type:  "slide_change",
                slide: presentation.current_slide,
              }.to_json)
            end
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

  router.websocket("/presentation", handler)

  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Presentación en Vivo</title>
          <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
          <style>
            .container {
              max-width: 800px;
              margin: 0 auto;
              padding: 20px;
            }
            .slide {
              min-height: 400px;
              border: 1px solid #ccc;
              padding: 40px;
              margin: 20px 0;
              font-size: 24px;
            }
            .controls {
              display: flex;
              gap: 10px;
              justify-content: center;
            }
            .controls button {
              padding: 10px 20px;
              font-size: 18px;
            }
            .status {
              text-align: center;
              color: #666;
              margin: 10px 0;
            }
            pre {
              background: #f5f5f5;
              padding: 10px;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="status" class="status">Conectando...</div>
            <div id="slide" class="slide"></div>
            <div id="controls" class="controls" style="display: none;">
              <button onclick="previousSlide()">← Anterior</button>
              <button onclick="nextSlide()">Siguiente →</button>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(`ws://localhost:8080/presentation?user_id=${userId}`);
            const slide = document.getElementById('slide');
            const controls = document.getElementById('controls');
            const status = document.getElementById('status');
            let presentation;
            let isPresenter = false;

            function updateSlide(slideNumber) {
              if (presentation && presentation.slides[slideNumber]) {
                slide.innerHTML = marked.parse(presentation.slides[slideNumber]);
              }
            }

            function nextSlide() {
              if (isPresenter) {
                ws.send(JSON.stringify({ action: 'next' }));
              }
            }

            function previousSlide() {
              if (isPresenter) {
                ws.send(JSON.stringify({ action: 'previous' }));
              }
            }

            // Manejar teclas para navegación
            document.addEventListener('keydown', (e) => {
              if (isPresenter) {
                if (e.key === 'ArrowRight') nextSlide();
                if (e.key === 'ArrowLeft') previousSlide();
              }
            });

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                  presentation = data.presentation;
                  isPresenter = data.is_presenter;
                  status.textContent = isPresenter ? 'Modo Presentador' : 'Modo Espectador';
                  controls.style.display = isPresenter ? 'flex' : 'none';
                  updateSlide(presentation.current_slide);
                  break;
                
                case 'slide_change':
                  updateSlide(data.slide);
                  break;
                
                case 'error':
                  status.textContent = `Error: ${data.message}`;
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
