require "../src/hauyna-web-socket"
require "http/server"

# Ejemplo de editor de código colaborativo simple

class Document
  include JSON::Serializable
  
  property content : String
  property version : Int32
  property last_editor : String?
  property cursors : Hash(String, Int32) # Posición del cursor por editor

  def initialize
    @content = ""
    @version = 0
    @last_editor = nil
    @cursors = {} of String => Int32
  end

  def update(operation : Operation, editor : String)
    apply_operation(operation)
    @version += 1
    @last_editor = editor
  end

  def update_cursor(editor : String, position : Int32)
    @cursors[editor] = position
  end

  private def apply_operation(operation : Operation)
    case operation.type
    when "insert"
      before = @content[0...operation.position]
      after = @content[operation.position..]
      @content = before + operation.text + after
    when "delete"
      before = @content[0...operation.position]
      after = @content[operation.position + operation.length]
      @content = before + after
    end
  end
end

class Operation
  include JSON::Serializable
  
  property type : String # "insert" o "delete"
  property position : Int32
  property text : String
  property length : Int32
  property editor : String
  property version : Int32

  def initialize(@type, @position, @text, @length, @editor, @version)
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
        case data["type"]?.try(&.as_s)
        when "update"
          if operation_data = data["operation"]?
            operation = Operation.new(
              type: operation_data["type"].as_s,
              position: operation_data["position"].as_i,
              text: operation_data["text"].as_s,
              length: operation_data["length"].as_i,
              editor: editor_id,
              version: operation_data["version"].as_i
            )
            
            document.update(operation, editor_id)
            
            Hauyna::WebSocket::Events.send_to_group("editors", {
              type: "operation",
              operation: operation
            }.to_json)
          end
        when "cursor"
          if position = data["position"]?.try(&.as_i)
            document.update_cursor(editor_id, position)
            
            Hauyna::WebSocket::Events.send_to_group("editors", {
              type: "cursor_update",
              editor: editor_id,
              position: position
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
            let localVersion = 0;
            let lastCursorPosition = 0;

            ws.onopen = () => {
              status.textContent = 'Conectado';
            };

            editor.addEventListener('input', (e) => {
              if (isUpdating) return;
              
              const position = editor.selectionStart;
              const change = getInputChange(e);
              
              if (change) {
                sendOperation(change);
              }
              
              lastCursorPosition = position;
            });

            editor.addEventListener('select', (e) => {
              const position = editor.selectionStart;
              if (position !== lastCursorPosition) {
                ws.send(JSON.stringify({
                  type: 'cursor',
                  position: position,
                  editor: editorId
                }));
                lastCursorPosition = position;
              }
            });

            function getInputChange(e) {
              const position = editor.selectionStart;
              
              if (e.inputType === 'insertText' || e.inputType === 'insertLineBreak') {
                return {
                  type: 'insert',
                  position: position - 1,
                  text: e.data || '\\n',
                  length: 1,
                  editor: editorId,
                  version: localVersion
                };
              } else if (e.inputType === 'deleteContentBackward') {
                return {
                  type: 'delete',
                  position: position,
                  text: '',
                  length: 1,
                  editor: editorId,
                  version: localVersion
                };
              }
              return null;
            }

            function sendOperation(operation) {
              ws.send(JSON.stringify({
                type: 'update',
                operation: operation
              }));
            }

            function applyOperation(operation) {
              isUpdating = true;
              const currentPosition = editor.selectionStart;
              
              if (operation.type === 'insert') {
                const before = editor.value.slice(0, operation.position);
                const after = editor.value.slice(operation.position);
                editor.value = before + operation.text + after;
                
                // Ajustar cursor si la inserción fue antes de nuestra posición
                if (operation.position < currentPosition) {
                  editor.selectionStart = editor.selectionEnd = currentPosition + operation.text.length;
                }
              } else if (operation.type === 'delete') {
                const before = editor.value.slice(0, operation.position);
                const after = editor.value.slice(operation.position + operation.length);
                editor.value = before + after;
                
                // Ajustar cursor si la eliminación fue antes de nuestra posición
                if (operation.position < currentPosition) {
                  editor.selectionStart = editor.selectionEnd = currentPosition - operation.length;
                }
              }
              
              isUpdating = false;
            }

            ws.onmessage = (event) => {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'error':
                  error.textContent = data.message;
                  setTimeout(() => error.textContent = '', 3000);
                  break;
                  
                case 'init':
                  isUpdating = true;
                  editor.value = data.document.content;
                  localVersion = data.document.version;
                  version.textContent = \`Versión: \${data.document.version}\`;
                  lastEditor.textContent = data.document.last_editor ? 
                    \`Último editor: \${data.document.last_editor}\` : '';
                  isUpdating = false;
                  break;
                  
                case 'operation':
                  if (data.operation.editor !== editorId) {
                    applyOperation(data.operation);
                    localVersion++;
                    version.textContent = \`Versión: \${localVersion}\`;
                    lastEditor.textContent = \`Último editor: \${data.operation.editor}\`;
                  }
                  break;
                  
                case 'cursor_update':
                  // Implementar visualización de cursores de otros usuarios si se desea
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