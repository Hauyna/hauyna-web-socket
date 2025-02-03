require "../spec_helper"

describe "Reconnection Integration" do
  it "handles socket reconnection" do
    old_socket = MockWebSocket.new
    new_socket = MockWebSocket.new
    channel = "test_channel"

    # Configurar socket original
    Hauyna::WebSocket::ConnectionManager.register(old_socket, "test_user")
    sleep 0.1.seconds

    Hauyna::WebSocket::Channel.subscribe(
      channel,
      old_socket,
      "test_user",
      {"user_id" => JSON::Any.new("test_user")}
    )

    # Esperar a que se procese la suscripción
    sleep 0.1.seconds

    # Registrar el nuevo socket antes de la reconexión
    Hauyna::WebSocket::ConnectionManager.register(new_socket, "test_user")
    sleep 0.1.seconds

    # Simular reconexión
    Hauyna::WebSocket::Channel.handle_reconnection(new_socket, old_socket)
    sleep 0.1.seconds

    # Verificar que el nuevo socket está registrado correctamente
    Hauyna::WebSocket::ConnectionManager.get_identifier(new_socket).should eq("test_user")
    Hauyna::WebSocket::Channel.subscribed?(channel, new_socket).should be_true
    Hauyna::WebSocket::Channel.subscribed?(channel, old_socket).should be_false
  end
end 