require "../spec_helper"

describe "Channel Integration" do
  before_each do
    # Reset channel state
    Hauyna::WebSocket::Channel.cleanup_all
  end

  it "handles channel subscriptions and broadcasts" do
    socket1 = MockWebSocket.new
    socket2 = MockWebSocket.new
    channel = "test_channel"

    # Registrar sockets
    Hauyna::WebSocket::ConnectionManager.register(socket1, "user1")
    Hauyna::WebSocket::ConnectionManager.register(socket2, "user2")
    sleep 0.1.seconds

    # Suscribir a canal
    Hauyna::WebSocket::Channel.subscribe(
      channel,
      socket1,
      "user1",
      {
        "user_id" => JSON::Any.new("user1"),
        "channel" => JSON::Any.new(channel)
      }
    )

    Hauyna::WebSocket::Channel.subscribe(
      channel,
      socket2,
      "user2",
      {
        "user_id" => JSON::Any.new("user2"),
        "channel" => JSON::Any.new(channel)
      }
    )

    sleep 0.1.seconds # Esperar que se procesen las suscripciones

    # Limpiar mensajes anteriores
    socket1.received_messages.clear
    socket2.received_messages.clear

    # Broadcast a canal
    message = {
      "type" => "broadcast",
      "content" => "hello",
      "channel" => channel
    }.to_json

    Hauyna::WebSocket::Channel.broadcast_to(channel, message)

    # Esperar procesamiento asíncrono
    sleep 0.1.seconds

    # Verificar que ambos sockets recibieron el mensaje
    socket1.received_messages.any? { |msg| msg.includes?("hello") }.should be_true
    socket2.received_messages.any? { |msg| msg.includes?("hello") }.should be_true

    # Desuscribir un socket
    Hauyna::WebSocket::Channel.unsubscribe(channel, socket1)
    sleep 0.1.seconds
    
    # Verificar desuscripción
    Hauyna::WebSocket::Channel.subscription_count(channel).should eq(1)
    Hauyna::WebSocket::Channel.subscribed?(channel, socket1).should be_false
  end
end 