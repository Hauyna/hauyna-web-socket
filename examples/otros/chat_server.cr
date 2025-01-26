require "../src/hauyna-web-socket"

# Crear manejador de WebSocket
handler = Hauyna::WebSocket::Handler.new(
  heartbeat_interval: 30.seconds,
  heartbeat_timeout: 60.seconds,

  # Extraer identificador del usuario
  extract_identifier: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    params["user_id"]?.try(&.as_s)
  },

  # Manejar nueva conexión
  on_open: ->(socket : HTTP::WebSocket, params : JSON::Any) {
    user_id = params["user_id"]?.try(&.as_s)
    room = params["room"]?.try(&.as_s) || "lobby"

    if user_id
      # Registrar usuario en la sala
      Hauyna::WebSocket::ConnectionManager.register(socket, user_id)
      Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, room)

      # Obtener lista de usuarios conectados
      connected_users = Hauyna::WebSocket::ConnectionManager.get_group_members(room).to_a
      puts "Usuarios conectados en #{room}: #{connected_users.inspect}"

      # Enviar mensaje de bienvenida al usuario
      socket.send({
        type:            "welcome",
        message:         "¡Bienvenido al chat!",
        user_id:         user_id,
        room:            room,
        connected_users: connected_users,
        online_users:    connected_users.size,
      }.to_json)

      # Notificar a otros usuarios sobre el nuevo usuario
      Hauyna::WebSocket::Events.send_to_group(room, {
        type:            "user_joined",
        user:            user_id,
        room:            room,
        connected_users: connected_users,
        timestamp:       Time.local.to_unix,
        online_users:    connected_users.size,
      }.to_json)
    end
  },

  # Manejar mensajes
  on_message: ->(socket : HTTP::WebSocket, data : JSON::Any) {
    case data["type"]?.try(&.as_s)
    when "chat_message"
      if room = data["room"]?.try(&.as_s)
        Hauyna::WebSocket::Events.send_to_group(room, {
          type:      "chat_message",
          user:      Hauyna::WebSocket::ConnectionManager.get_identifier(socket),
          message:   data["message"],
          timestamp: Time.local.to_unix,
        }.to_json)
      end
    when "change_room"
      if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
        if new_room = data["new_room"]?.try(&.as_s)
          if old_room = data["old_room"]?.try(&.as_s)
            Hauyna::WebSocket::ConnectionManager.remove_from_group(user_id, old_room)
            # Notificar a la sala anterior
            old_room_users = Hauyna::WebSocket::ConnectionManager.get_group_members(old_room)
            Hauyna::WebSocket::Events.send_to_group(old_room, {
              type:         "user_left",
              user:         user_id,
              room:         old_room,
              online_users: old_room_users.size,
            }.to_json)
          end

          Hauyna::WebSocket::ConnectionManager.add_to_group(user_id, new_room)
          connected_users = Hauyna::WebSocket::ConnectionManager.get_group_members(new_room).to_a

          # Notificar a la nueva sala
          Hauyna::WebSocket::Events.send_to_group(new_room, {
            type:         "user_joined",
            user:         user_id,
            room:         new_room,
            online_users: connected_users.size,
          }.to_json)

          # Enviar lista actualizada de usuarios al que cambió de sala
          socket.send({
            type:            "room_users",
            room:            new_room,
            connected_users: connected_users,
            online_users:    connected_users.size,
          }.to_json)
        end
      end
    end
  },

  # Manejar desconexión
  on_close: ->(socket : HTTP::WebSocket) {
    if user_id = Hauyna::WebSocket::ConnectionManager.get_identifier(socket)
      # Obtener las salas del usuario antes de desconectarlo
      rooms = Hauyna::WebSocket::ConnectionManager.get_user_groups(user_id)

      # Notificar a cada sala
      rooms.each do |room|
        members = Hauyna::WebSocket::ConnectionManager.get_group_members(room)
        members.delete(user_id) # Excluir al usuario que se va

        Hauyna::WebSocket::Events.send_to_group(room, {
          type:         "user_left",
          user:         user_id,
          room:         room,
          timestamp:    Time.local.to_unix,
          online_users: members.size,
        }.to_json)
      end

      # Desregistrar al usuario
      Hauyna::WebSocket::ConnectionManager.unregister(socket)
    end
  }
)

# Configurar rutas
router = Hauyna::WebSocket::Router.new
router.websocket("/chat", handler)

# Iniciar servidor
server = HTTP::Server.new do |context|
  router.call(context)
end

puts "Chat server running on http://localhost:3000"
server.listen("0.0.0.0", 3000)
