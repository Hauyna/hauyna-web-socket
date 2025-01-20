require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de editor de código colaborativo simple

class Document
  include JSON::Serializable
  
  property content : String
  property version : Int32
  property last_editor : String?

  def initialize
    @content = ""
    @version = 0
    @last_editor = nil
  end

  def update(new_content : String, editor : String)
    @content = new_content
    @version += 1
    @last_editor = editor
  end
end

document = Document.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["editor_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if editor_id = params["editor_id"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.add_to_group(editor_id, "editors")
      socket.send({
        type: "init",
        document: document
      }.to_json)
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if editor_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        if data["type"]?.try(&.as_s) == "update"
          if content = data["content"]?.try(&.as_s)
            document.update(content, editor_id)
            Hauyna::WebSocket::Events.send_to_group("editors", {
              type: "document_update",
              document: document
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

  router.websocket("/edit", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Editor Colaborativo</title>
          <style>
            .editor-container {
              display: flex;
              flex-direction: column;
              gap: 10px;
              padding: 20px;
              max-width: 800px;
              margin: 0 auto;
            }
            #editor {
              width: 100%;
              height: 400px;
              font-family: monospace;
              padding: 10px;
              resize: vertical;
            }
            .status-bar {
              display: flex;
              justify-content: space-between;
              background: #f5f5f5;
              padding: 10px;
              border-radius: 4px;
            }
            .error {
              color: red;
              margin-top: 10px;
            }
          </style>
        </head>
        <body>
          <div class="editor-container">
            <div class="status-bar">
              <span id="status">Conectando...</span>
              <span id="version"></span>
              <span id="last-editor"></span>
            </div>
            <textarea id="editor" spellcheck="false"></textarea>
            <div id="error" class="error"></div>
          </div>

          <script>
            const editorId = Math.random().toString(36).substr(2, 9);
            const ws = new WebSocket(\`ws://localhost:8080/edit?editor_id=\${editorId}\`);
            const editor = document.getElementById('editor');
            const status = document.getElementById('status');
            const version = document.getElementById('version');
            const lastEditor = document.getElementById('last-editor');
            const error = document.getElementById('error');
            
            let isUpdating = false;
            let updateTimeout;

            ws.onopen = () => {
              status.textContent = 'Conectado';
            };

            editor.addEventListener('input', () => {
              if (isUpdating) return;
              
              clearTimeout(updateTimeout);
              updateTimeout = setTimeout(() => {
                ws.send(JSON.stringify({
                  type: 'update',
                  content: editor.value
                }));
              }, 500);
            });

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              if (data.type === 'error') {
                error.textContent = data.message;
                setTimeout(() => error.textContent = '', 3000);
              } else if (data.type === 'init' || data.type === 'document_update') {
                isUpdating = true;
                editor.value = data.document.content;
                version.textContent = \`Versión: \${data.document.version}\`;
                lastEditor.textContent = data.document.last_editor ? 
                  \`Último editor: \${data.document.last_editor}\` : '';
                isUpdating = false;
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