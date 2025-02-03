require "../spec_helper"

describe "Connection Integration" do
  it "handles basic connection lifecycle" do
    socket = MockWebSocket.new
    handler = Hauyna::WebSocket::Handler.new(
      extract_identifier: ->(ws : HTTP::WebSocket, params : JSON::Any) { "test_user" },
      on_open: ->(ws : HTTP::WebSocket, params : JSON::Any) {
        Hauyna::WebSocket::ConnectionManager.register(ws, "test_user")
      }
    )

    # Simular conexión
    handler.call(socket, {"channel" => JSON::Any.new("test")})
    
    # Verificar que el socket está registrado
    Hauyna::WebSocket::ConnectionManager.get_identifier(socket).should eq("test_user")
    
    # Simular desconexión usando directamente ConnectionManager
    Hauyna::WebSocket::ConnectionManager.cleanup_socket(socket)
    
    # Dar tiempo para que se procese la operación asíncrona
    sleep 0.1
    
    # Verificar limpieza
    Hauyna::WebSocket::ConnectionManager.get_identifier(socket).should be_nil
  end
end 