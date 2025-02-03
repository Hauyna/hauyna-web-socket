require "../spec_helper"

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