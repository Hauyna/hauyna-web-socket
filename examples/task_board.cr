require "../src/hauyna-web-socket"
require "http/server"

# Sistema de tablero de tareas colaborativo tipo Kanban

class Task
  include JSON::Serializable
  
  property id : String
  property title : String
  property description : String
  property status : String # todo, doing, done
  property assigned_to : String?
  property created_by : String
  property created_at : Time
  property updated_at : Time
  property comments : Array(Comment)
  
  def initialize(@title : String, @description : String, @created_by : String)
    @id = Random::Secure.hex(8)
    @status = "todo"
    @assigned_to = nil
    @created_at = Time.local
    @updated_at = Time.local
    @comments = [] of Comment
  end
end

class Comment
  include JSON::Serializable
  
  property id : String
  property text : String
  property user_id : String
  property created_at : Time
  
  def initialize(@text : String, @user_id : String)
    @id = Random::Secure.hex(8)
    @created_at = Time.local
  end
end

class Board
  include JSON::Serializable
  
  property tasks : Hash(String, Task)
  property users : Hash(String, String) # user_id => name
  property activity_log : Array(String)
  
  def initialize
    @tasks = {} of String => Task
    @users = {} of String => String
    @activity_log = [] of String
  end
  
  def add_task(task : Task)
    @tasks[task.id] = task
    log_activity("#{@users[task.created_by]} creó la tarea '#{task.title}'")
  end
  
  def update_task(task_id : String, status : String, assigned_to : String?)
    if task = @tasks[task_id]?
      old_status = task.status
      old_assigned = task.assigned_to
      
      task.status = status
      task.assigned_to = assigned_to
      task.updated_at = Time.local
      
      if old_status != status
        log_activity("Tarea '#{task.title}' movida a #{status}")
      end
      
      if old_assigned != assigned_to && assigned_to
        log_activity("Tarea '#{task.title}' asignada a #{@users[assigned_to]}")
      end
    end
  end
  
  def add_comment(task_id : String, comment : Comment)
    if task = @tasks[task_id]?
      task.comments << comment
      log_activity("#{@users[comment.user_id]} comentó en '#{task.title}'")
    end
  end
  
  private def log_activity(message : String)
    @activity_log.unshift("#{Time.local.to_s("%H:%M:%S")} - #{message}")
    @activity_log = @activity_log.first(50) # Mantener solo los últimos 50 registros
  end
end

board = Board.new

server = HTTP::Server.new do |context|
  router = Hauyna::WebSocket::Router.new
  handler = Hauyna::WebSocket::Handler.new

  handler.extract_identifier = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    params["user_id"]?.try(&.as_s)
  }

  handler.on_open = ->(socket : HTTP::WebSocket, params : Hash(String, JSON::Any)) {
    if user_id = params["user_id"]?.try(&.as_s)
      if name = params["name"]?.try(&.as_s)
        board.users[user_id] = name
        Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, "users")
        
        socket.send({
          type: "init",
          board: board
        }.to_json)
      end
    end
  }

  handler.on_message = ->(socket : HTTP::WebSocket, message : String) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      begin
        data = JSON.parse(message)
        case data["type"]?.try(&.as_s)
        when "create_task"
          task = Task.new(
            title: data["title"].as_s,
            description: data["description"].as_s,
            created_by: user_id
          )
          board.add_task(task)
          
        when "update_task"
          board.update_task(
            task_id: data["task_id"].as_s,
            status: data["status"].as_s,
            assigned_to: data["assigned_to"]?.try(&.as_s)
          )
          
        when "add_comment"
          comment = Comment.new(
            text: data["text"].as_s,
            user_id: user_id
          )
          board.add_comment(data["task_id"].as_s, comment)
        end
        
        Hauyna::WebSocket::Events.send_to_group("users", {
          type: "board_update",
          board: board
        }.to_json)
      rescue ex
        socket.send({
          type: "error",
          message: ex.message
        }.to_json)
      end
    end
  }

  router.websocket("/board", handler)
  
  next if router.call(context)

  if context.request.path == "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Tablero de Tareas</title>
          <style>
            .container {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
            }
            .board {
              display: grid;
              grid-template-columns: repeat(3, 1fr);
              gap: 20px;
              margin: 20px 0;
            }
            .column {
              background: #f5f5f5;
              padding: 15px;
              border-radius: 4px;
              min-height: 200px;
            }
            .column-header {
              font-size: 18px;
              font-weight: bold;
              margin-bottom: 10px;
              padding-bottom: 10px;
              border-bottom: 2px solid #ddd;
            }
            .task {
              background: white;
              padding: 15px;
              margin-bottom: 10px;
              border-radius: 4px;
              box-shadow: 0 2px 4px rgba(0,0,0,0.1);
              cursor: move;
            }
            .task-header {
              display: flex;
              justify-content: space-between;
              margin-bottom: 10px;
            }
            .task-title {
              font-weight: bold;
            }
            .task-assign {
              color: #666;
              cursor: pointer;
            }
            .task-description {
              color: #666;
              margin-bottom: 10px;
            }
            .comments {
              margin-top: 10px;
              padding-top: 10px;
              border-top: 1px solid #eee;
            }
            .comment {
              font-size: 14px;
              margin-bottom: 5px;
            }
            .activity-log {
              background: #f9f9f9;
              padding: 15px;
              margin-top: 20px;
              border-radius: 4px;
              max-height: 200px;
              overflow-y: auto;
            }
            .activity-item {
              font-size: 14px;
              color: #666;
              margin-bottom: 5px;
            }
            .new-task {
              margin-bottom: 20px;
            }
            .new-task input,
            .new-task textarea {
              width: 100%;
              margin-bottom: 10px;
              padding: 8px;
            }
            #error {
              color: red;
              margin: 10px 0;
            }
            .column-content {
              min-height: 100px;
            }
            .task.dragging {
              opacity: 0.5;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <div id="join" style="text-align: center;">
              <h2>Unirse al Tablero</h2>
              <input type="text" id="name" placeholder="Tu nombre">
              <button onclick="joinBoard()">Entrar</button>
            </div>
            
            <div id="board-container" style="display: none;">
              <div class="new-task">
                <input type="text" id="task-title" placeholder="Título de la tarea">
                <textarea id="task-description" placeholder="Descripción"></textarea>
                <button onclick="createTask()">Crear Tarea</button>
              </div>
              
              <div class="board">
                <div class="column" ondragover="allowDrop(event)" ondrop="drop(event)" data-status="todo">
                  <div class="column-header">Por Hacer</div>
                  <div id="todo" class="column-content"></div>
                </div>
                <div class="column" ondragover="allowDrop(event)" ondrop="drop(event)" data-status="doing">
                  <div class="column-header">En Progreso</div>
                  <div id="doing" class="column-content"></div>
                </div>
                <div class="column" ondragover="allowDrop(event)" ondrop="drop(event)" data-status="done">
                  <div class="column-header">Completado</div>
                  <div id="done" class="column-content"></div>
                </div>
              </div>
              
              <div class="activity-log">
                <h3>Actividad Reciente</h3>
                <div id="activity"></div>
              </div>
            </div>
          </div>

          <script>
            const userId = Math.random().toString(36).substr(2, 9);
            let ws;
            let board;
            
            function joinBoard() {
              const name = document.getElementById('name').value.trim();
              if (!name) return;
              
              document.getElementById('join').style.display = 'none';
              document.getElementById('board-container').style.display = 'block';
              
              ws = new WebSocket(
                \`ws://localhost:8080/board?user_id=\${userId}&name=\${name}\`
              );
              
              ws.onmessage = handleMessage;
            }
            
            function createTask() {
              const title = document.getElementById('task-title').value.trim();
              const description = document.getElementById('task-description').value.trim();
              
              if (!title) return;
              
              ws.send(JSON.stringify({
                type: 'create_task',
                title: title,
                description: description
              }));
              
              document.getElementById('task-title').value = '';
              document.getElementById('task-description').value = '';
            }
            
            function updateTask(taskId, status, assignedTo = null) {
              ws.send(JSON.stringify({
                type: 'update_task',
                task_id: taskId,
                status: status,
                assigned_to: assignedTo
              }));
            }
            
            function addComment(taskId) {
              const text = prompt('Escribe tu comentario:');
              if (text) {
                ws.send(JSON.stringify({
                  type: 'add_comment',
                  task_id: taskId,
                  text: text
                }));
              }
            }
            
            function allowDrop(event) {
              event.preventDefault();
            }
            
            function drag(event, taskId) {
              event.dataTransfer.setData('task_id', taskId);
              event.target.classList.add('dragging');
            }
            
            function drop(event) {
              event.preventDefault();
              const taskId = event.dataTransfer.getData('task_id');
              const newStatus = event.currentTarget.dataset.status;
              
              document.querySelector('.dragging')?.classList.remove('dragging');
              
              updateTask(taskId, newStatus);
            }
            
            function createTaskElement(task) {
              const div = document.createElement('div');
              div.className = 'task';
              div.draggable = true;
              div.ondragstart = (e) => drag(e, task.id);
              div.ondragend = (e) => e.target.classList.remove('dragging');
              
              div.innerHTML = \`
                <div class="task-header">
                  <span class="task-title">\${task.title}</span>
                  <span class="task-assign" onclick="updateTask('\${task.id}', '\${task.status}', userId)">
                    \${task.assigned_to && board.users[task.assigned_to] ? board.users[task.assigned_to] : 'Asignar'}
                  </span>
                </div>
                <div class="task-description">\${task.description}</div>
                <div class="comments">
                  \${task.comments.map(comment => \`
                    <div class="comment">
                      <strong>\${board.users[comment.user_id] || 'Usuario Desconocido'}:</strong>
                      \${comment.text}
                    </div>
                  \`).join('')}
                  <button onclick="addComment('\${task.id}')">Comentar</button>
                </div>
              \`;
              
              return div;
            }
            
            function updateBoard() {
              ['todo', 'doing', 'done'].forEach(status => {
                const container = document.getElementById(status);
                container.innerHTML = '';
                
                Object.values(board.tasks)
                  .filter(task => task.status === status)
                  .forEach(task => {
                    container.appendChild(createTaskElement(task));
                  });
              });
              
              document.getElementById('activity').innerHTML = 
                board.activity_log.map(item => \`
                  <div class="activity-item">\${item}</div>
                \`).join('');
            }
            
            function handleMessage(event) {
              const data = JSON.parse(event.data);
              
              switch(data.type) {
                case 'init':
                case 'board_update':
                  board = data.board;
                  updateBoard();
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