require "../spec_helper"
require "log"

describe "Error Handling" do
  it "handles validation errors" do
    socket = MockWebSocket.new
    error = Hauyna::WebSocket::MessageValidator::ValidationError.new("Invalid message")
    
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    message = JSON.parse(socket.received_messages.first)
    message["type"].should eq("error")
    message["error_type"].should eq("validation_error")
  end

  it "handles connection errors" do
    socket = MockWebSocket.new
    error = IO::Error.new("Connection lost")
    
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    message = JSON.parse(socket.received_messages.first)
    message["type"].should eq("error")
    message["error_type"].should eq("connection_error")
  end

  it "handles unexpected errors" do
    socket = MockWebSocket.new
    error = Exception.new("Unexpected error")
    
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    message = JSON.parse(socket.received_messages.first)
    message["type"].should eq("error")
    message["error_type"].should eq("internal_error")
  end
end

describe Hauyna::WebSocket::ErrorHandler do
  it "handles IO::Error properly" do
    socket = MockWebSocket.new
    error = IO::Error.new("Test IO error")
    
    # Register socket
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    sleep 0.1.seconds

    # Handle error
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    # Socket should be closed with appropriate code
    socket.closed.should be_true
    socket.close_code.should eq(1006) # Abnormal closure
  end

  it "handles Socket::Error properly" do
    socket = MockWebSocket.new
    error = Socket::Error.new("Test socket error")
    
    # Register socket
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    sleep 0.1.seconds

    # Handle error
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    # Socket should be closed
    socket.closed.should be_true
    socket.close_code.should eq(1006)
  end

  it "handles generic errors with logging" do
    socket = MockWebSocket.new
    error = Exception.new("Test generic error")
    log_io = IO::Memory.new
    
    # Register socket
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    sleep 0.1.seconds

    # Configure logging to use our IO
    backend = Log::IOBackend.new(log_io)
    Log.setup(:error, backend)
    
    # Handle error
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    
    # Verify error was logged
    log_io.to_s.should contain("Test generic error")
    
    # Socket should be closed
    socket.closed.should be_true
    
    # Reset logging to default
    Log.setup(:error, Log::IOBackend.new)
  end

  it "cleans up resources after error" do
    socket = MockWebSocket.new
    channel = "test_channel"
    error = IO::Error.new("Test cleanup error")
    
    # Setup test state
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    Hauyna::WebSocket::Channel.subscribe(
      channel,
      socket,
      "test_user",
      {"user_id" => JSON::Any.new("test_user")}
    )
    sleep 0.1.seconds

    # Handle error
    Hauyna::WebSocket::ErrorHandler.handle(socket, error)
    sleep 0.1.seconds
    
    # Verify cleanup
    Hauyna::WebSocket::Channel.subscribed?(channel, socket).should be_false
    Hauyna::WebSocket::ConnectionManager.get_identifier(socket).should be_nil
  end
end 