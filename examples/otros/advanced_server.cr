require "../src/hauyna-web-socket"

# Configurar eventos personalizados
Hauyna::WebSocket::Events.on("user_typing") do |socket, data|
  # Notificar a otros usuarios en la sala que alguien está escribiendo
  if room = data["room"]?.try(&.as_s)
    if user = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      Hauyna::WebSocket::Events.send_to_group(room, {
        type: "user_typing",
        user: user,
        status: data["status"]
      }.to_json)
    end
  end
end

Hauyna::WebSocket::Events.on("change_room") do |socket, data|
  if user = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    # Salir de la sala actual
    if old_room = data["old_room"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.remove_from_group(user, old_room)
      Hauyna::WebSocket::Events.send_to_group(old_room, {
        type: "user_left_room",
        user: user,
        room: old_room
      }.to_json)
    end

    # Entrar a la nueva sala
    if new_room = data["new_room"]?.try(&.as_s)
      Hauyna::WebSocket::ConnectionManager.add_to_group(user, new_room)
      Hauyna::WebSocket::Events.send_to_group(new_room, {
        type: "user_joined_room",
        user: user,
        room: new_room
      }.to_json)
    end
  end
end

# Agregar el evento join_room
Hauyna::WebSocket::Events.on("join_room") do |socket, data|
  if user = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    if room = data["room"]?.try(&.as_s)
      # Agregar usuario a la sala
      Hauyna::WebSocket::ConnectionManager.add_to_group(user, room)
      
      # Obtener lista de usuarios en la sala
      members = Hauyna::WebSocket::ConnectionManager.get_group_members(room)
      
      # Notificar al usuario que se unió
      socket.send({
        type: "room_joined",
        room: room,
        users: members.to_a,
        online_users: members.size
      }.to_json)

      # Notificar a otros usuarios
      Hauyna::WebSocket::Events.send_to_group(room, {
        type: "user_joined",
        user: user,
        room: room,
        online_users: members.size
      }.to_json)
    end
  end
end

# Crear el manejador WebSocket con todas las callbacks
handler = Hauyna::WebSocket::Handler.new(
  # Extraer identificador único del usuario
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) : String? {
    # Asegurarnos de que el user_id sea string
    case user_id = params["user_id"]?
    when String
      user_id
    when JSON::Any
      user_id.to_s
    else
      "user_#{Random::Secure.hex(4)}"
    end
  },

  # Manejar nueva conexión
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    user_id = case id = params["user_id"]?
              when String
                id
              when JSON::Any
                id.to_s
              else
                "user_#{Random::Secure.hex(4)}"
              end

    room = case r = params["room"]?
           when String
             r
           when JSON::Any
             r.to_s
           else
             "lobby"
           end
    
    if user_id
      # Registrar usuario en la sala
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, room)
      
      # Obtener lista de usuarios actual
      members = Hauyna::WebSocket::ConnectionManager.get_group_members(room)
      
      # Enviar mensaje de bienvenida al usuario con la lista de usuarios
      socket.send({
        type: "welcome",
        message: "¡Bienvenido al chat!",
        user_id: user_id,
        room: room,
        users: members.to_a, # Convertir el Set a Array
        online_users: members.size
      }.to_json)

      # Notificar a otros usuarios
      Hauyna::WebSocket::Events.send_to_group(room, {
        type: "user_joined",
        user: user_id,
        room: room,
        users: members.to_a, # Convertir el Set a Array
        timestamp: Time.local.to_unix,
        online_users: members.size
      }.to_json)
    end
  },

  # Manejar mensajes recibidos
  on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
    user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
    
    case data["type"]?.try(&.as_s)
    when "chat_message"
      if room = data["room"]?.try(&.as_s)
        # Verificar que el usuario está en la sala
        if Hauyna::WebSocket::ConnectionManager.is_in_group?(user_id, room)
          members = Hauyna::WebSocket::ConnectionManager.get_group_members(room)
          
          # Enviar mensaje a todos en la sala, incluyendo el remitente
          Hauyna::WebSocket::Events.send_to_group(room, {
            type: "chat_message",
            user: user_id,
            room: room,
            message: data["message"]?.try(&.as_s) || "",
            timestamp: Time.local.to_unix,
            online_users: members.size
          }.to_json)
        end
      end
    when "private_message"
      if recipient = data["to"]?.try(&.as_s)
        # Enviar al destinatario
        Hauyna::WebSocket::Events.send_to_one(recipient, {
          type: "private_message",
          from: user_id,
          to: recipient,
          message: data["message"]?.try(&.as_s) || "",
          timestamp: Time.local.to_unix
        }.to_json)
        
        # Enviar copia al remitente
        socket.send({
          type: "private_message",
          from: user_id,
          to: recipient,
          message: data["message"]?.try(&.as_s) || "",
          timestamp: Time.local.to_unix
        }.to_json)
      end
    when "join_room", "change_room", "user_typing"
      # Disparar eventos personalizados
      Hauyna::WebSocket::Events.trigger_event(
        data["type"].as_s,
        socket,
        data.as_h
      )
    end
  },

  # Manejar desconexión
  on_close: ->(socket : HTTP::WebSocket) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      # Notificar a todos los grupos donde estaba el usuario
      Hauyna::WebSocket::ConnectionManager.get_user_groups(user_id).each do |room|
        members = Hauyna::WebSocket::ConnectionManager.get_group_members(room)
        Hauyna::WebSocket::Events.send_to_group(room, {
          type: "user_left",
          user: user_id,
          timestamp: Time.local.to_unix,
          online_users: members.size - 1
        }.to_json)
      end
    end
  },

  # Manejar ping (heartbeat)
  on_ping: ->(socket : HTTP::WebSocket, message : String) {
    # Registrar actividad del usuario
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      puts "Ping recibido de #{user_id}: #{message}"
    end
  },

  # Manejar pong (respuesta al heartbeat)
  on_pong: ->(socket : HTTP::WebSocket, message : String) {
    # Actualizar último tiempo de actividad
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      puts "Pong recibido de #{user_id}: #{message}"
    end
  }
)

# Configurar el router
router = Hauyna::WebSocket::Router.new
router.websocket("/chat", handler)

# Iniciar el servidor
server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Iniciando servidor WebSocket..."
puts "URL del WebSocket: ws://localhost:3000/chat"
puts "Servidor HTTP corriendo en http://localhost:3000"

# Agregar manejo de errores básico
begin
  server.listen("0.0.0.0", 3000)
rescue ex
  puts "Error iniciando el servidor: #{ex.message}"
  exit(1)
end 