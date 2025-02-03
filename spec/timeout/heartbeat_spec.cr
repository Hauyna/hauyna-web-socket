require "../spec_helper"

describe "Heartbeat" do
  it "detects connection timeout" do
    socket = MockWebSocket.new
    handler = Hauyna::WebSocket::Handler.new(
      heartbeat_interval: 0.1.seconds,
      heartbeat_timeout: 0.2.seconds,
      extract_identifier: ->(ws : HTTP::WebSocket, params : JSON::Any) { "test_user" },
      on_open: ->(ws : HTTP::WebSocket, params : JSON::Any) {
        Hauyna::WebSocket::ConnectionManager.register(ws, "test_user")
      },
      on_close: ->(ws : HTTP::WebSocket) {
        Hauyna::WebSocket::ConnectionManager.unregister(ws)
      }
    )

    # Simular conexión y activar heartbeat
    handler.call(socket, {"channel" => JSON::Any.new("test")})
    
    # Forzar timeout
    sleep 0.3.seconds
    
    # Verificar que el socket fue cerrado por timeout
    socket.closed.should be_true
  end

  it "maintains connection with active pings" do
    socket = MockWebSocket.new
    handler = Hauyna::WebSocket::Handler.new(
      heartbeat_interval: 0.1.seconds,
      heartbeat_timeout: 0.2.seconds,
      extract_identifier: ->(ws : HTTP::WebSocket, params : JSON::Any) { "test_user" },
      on_open: ->(ws : HTTP::WebSocket, params : JSON::Any) {
        Hauyna::WebSocket::ConnectionManager.register(ws, "test_user")
      }
    )

    # Simular conexión
    handler.call(socket, {"channel" => JSON::Any.new("test")})
    
    # Simular pings activos
    3.times do
      sleep 0.05.seconds
      handler.on_pong.try &.call(socket, "")
    end
    
    socket.closed.should be_false
  end
end 