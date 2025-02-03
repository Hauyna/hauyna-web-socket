require "spec"
require "../src/hauyna-web-socket"

# Helper para simular WebSockets
class MockWebSocket < HTTP::WebSocket
  property received_messages : Array(String)
  property closed : Bool
  property close_code : Int32?
  property close_message : String?
  
  def initialize
    super(IO::Memory.new)  # Inicializar la clase padre con un IO::Memory
    @received_messages = [] of String
    @closed = false
    @close_code = nil
    @close_message = nil
  end

  def send(message)
    @received_messages << message
  end

  def close(code = nil, message = nil)
    @closed = true
    @close_code = code
    @close_message = message
  end
end 