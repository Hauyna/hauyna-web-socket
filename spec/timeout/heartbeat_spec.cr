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

describe Hauyna::WebSocket::Heartbeat do
  it "properly records and validates pongs" do
    socket = MockWebSocket.new
    heartbeat = Hauyna::WebSocket::Heartbeat.new(
      interval: 1.seconds,
      timeout: 3.seconds
    )

    # Register socket and start heartbeat
    heartbeat.start(socket)
    sleep 0.1.seconds

    # Record a pong and check state
    heartbeat.record_pong(socket)
    
    # Socket should not be closed
    socket.closed.should be_false

    # Wait past timeout without pong
    sleep 4.seconds
    
    # Socket should be closed due to timeout
    socket.closed.should be_true
    socket.close_code.should eq(4000) # Heartbeat timeout
  end

  it "handles concurrent pong recordings safely" do
    socket = MockWebSocket.new
    heartbeat = Hauyna::WebSocket::Heartbeat.new(
      interval: 1.seconds,
      timeout: 3.seconds
    )

    # Start heartbeat
    heartbeat.start(socket)
    sleep 0.1.seconds

    # Simulate concurrent pong recordings
    10.times do
      spawn do
        heartbeat.record_pong(socket)
      end
    end

    # Wait for spawns to complete
    sleep 0.5.seconds
    
    # Socket should still be open
    socket.closed.should be_false
  end

  it "properly cleans up inactive connections" do
    socket1 = MockWebSocket.new
    socket2 = MockWebSocket.new
    heartbeat = Hauyna::WebSocket::Heartbeat.new(
      interval: 0.5.seconds,  # Shorter interval for faster test
      timeout: 1.seconds      # Shorter timeout for faster test
    )

    # Start heartbeat for both sockets
    heartbeat.start(socket1)
    heartbeat.start(socket2)

    # Record pong for socket1 and keep it active
    spawn do
      # Keep socket1 alive with regular pongs
      3.times do
        heartbeat.record_pong(socket1)
        sleep 0.3.seconds  # Pong more frequently than the timeout
      end
    end
    
    # Wait for socket2 to timeout but socket1 to stay alive
    sleep 1.5.seconds

    # socket1 should be alive (kept alive by regular pongs), socket2 should be closed
    socket1.closed.should be_false
    socket2.closed.should be_true
    socket2.close_code.should eq(4000) # Heartbeat timeout
  end
end 