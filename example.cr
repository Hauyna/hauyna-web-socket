require "./src/*"
# Registrar un evento
Hauyna::WebSocket::Events.on("user_joined") do |socket, data|
    # data es un JSON::Any
    username = data["username"].as_s
    puts "Nuevo usuario unido: #{username}"
  end
  
  # Disparar un evento
  event_data = JSON.parse(%({"username": "juan", "room": "general"}))
  Hauyna::WebSocket::Events.trigger_event("user_joined", socket, event_data)