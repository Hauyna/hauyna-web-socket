require "http/server"
require "./../../src/opal-web-socket"
require "uuid"
require "json"

# Para almacenar las conexiones de los clientes por 'user_id'
clients = {} of String => HTTP::WebSocket

# Crear el router WebSocket
router = Hauyna::WebSocket::Router.new

# Definir la ruta WebSocket "/chat"
router.websocket "/chat", Hauyna::WebSocket::Handler.new(
  # Cuando un cliente se conecta
  on_open: ->(socket : HTTP::WebSocket) do
    puts "Conexión WebSocket abierta: #{socket.object_id}"
  end,

  # Cuando un cliente envía un mensaje
  on_message: ->(socket : HTTP::WebSocket, message : String) do
    begin
      data = JSON.parse(message).as_h
      puts "Mensaje recibido: #{data.inspect}"

      # Verificar si 'type' y 'user_id' están presentes

      puts !data.has_key?("type")
      puts !data.has_key?("user_id")

      if !data.has_key?("type") || !(!data.has_key?("user_id" && !data.has_key?("sender")))
        socket.send({type: "error", message: "Faltan datos en el mensaje."}.to_json)
        return
      end

      if data["type"] == "set_user_id" && data["user_id"].to_s != ""
        user_id = data["user_id"].to_s
        puts "Registrando usuario: #{user_id}"

        # Guardar el socket en el Hash de 'clients'
        clients[user_id] = socket
        socket.send({type: "user_list", users: clients.keys}.to_json)
        Hauyna::WebSocket::Events.trigger_event("user_set", socket, JSON.parse({"user_id" => user_id}.to_json))
      elsif data["type"] == "chat_message"
        # Asegurarse de que los datos del mensaje son válidos
        sender = data["sender"]
        recipient = data["recipient"]
        message = data["message"]

        if sender.nil? || recipient.nil? || message.nil?
          socket.send({type: "error", message: "Mensaje de chat incompleto."}.to_json)
          return
        end

        # Imprimir en consola el mensaje que llega
        puts "Mensaje de #{sender} para #{recipient}: #{message}"

        # Si el destinatario está conectado, enviarle el mensaje
        if clients[recipient]
          clients[recipient].send({type: "chat_message", sender: sender, message: message}.to_json)
        else
          # Si el destinatario no está conectado, avisar al remitente
          socket.send({type: "error", message: "Usuario no encontrado."}.to_json)
        end
      else
        socket.send({type: "error", message: "Tipo de mensaje no reconocido."}.to_json)
      end
    rescue JSON::ParseException
      socket.send({type: "error", message: "Error al parsear el mensaje."}.to_json)
    rescue KeyError
      socket.send({type: "error", message: "Error en el mensaje:"}.to_json)
    end
  end,

  # Cuando un cliente se desconecta
  on_close: ->(socket : HTTP::WebSocket) do
    # Buscar y eliminar al cliente desconectado de la lista
    clients.each do |user_id, client_socket|
      if client_socket == socket
        clients.delete(user_id)
        puts "Cliente con user_id #{user_id} desconectado."
        break
      end
    end

    # Imprimir la lista de usuarios conectados después de que un usuario se desconecte
    puts "Usuarios conectados: #{clients.keys.join(", ")}"
    # Enviar la lista actualizada de usuarios a todos los clientes
    clients.each_value do |client_socket|
      client_socket.send({type: "user_list", users: clients.keys}.to_json)
    end
  end
)

# Registrar eventos personalizados

# Evento cuando un nuevo usuario se conecta
Hauyna::WebSocket::Events.on("user_set") do |socket, data|
  user_id = data["user_id"]
  puts "Usuario registrado con ID: #{user_id}"
  socket.send({type: "success", message: "Usuario #{user_id} registrado correctamente."}.to_json)
  clients.each_value do |client_socket|
    client_socket.send({type: "user_list", users: clients.keys}.to_json)
  end
end

# Evento para el chat, se envía cuando un mensaje es entregado con éxito
Hauyna::WebSocket::Events.on("chat_message") do |socket, data|
  sender = data["sender"]
  recipient = data["recipient"]
  message = data["message"]
  puts "Mensaje de #{sender} a #{recipient}: #{message}"
  socket.send({type: "chat_message", sender: sender, recipient: recipient, message: message}.to_json)
end

# Configuración del servidor HTTP
server = HTTP::Server.new do |context|
  if router.call(context)
    # La solicitud fue manejada por el router WebSocket
  else
    context.response.content_type = "text/plain"
    context.response.print "Ruta no encontrada"
  end
end

# Vinculamos el servidor en la IP y puerto especificados
address = server.bind_tcp "0.0.0.0", 8080
puts "Servidor escuchando en http://#{address}"

# Escuchar peticiones entrantes
server.listen
