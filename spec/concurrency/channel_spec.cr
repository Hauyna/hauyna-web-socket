require "../spec_helper"

describe "Channel Concurrency" do
  it "handles multiple concurrent subscriptions" do
    channel = "test_channel"
    sockets = Array.new(10) { MockWebSocket.new }
    
    # Crear múltiples suscripciones concurrentemente
    spawn do
      sockets.each_with_index do |socket, i|
        Hauyna::WebSocket::Channel.subscribe(
          channel,
          socket,
          "user_#{i}",
          {"user_id" => JSON::Any.new("user_#{i}")}
        )
      end
    end

    # Esperar a que se procesen todas las suscripciones
    sleep 0.1.seconds

    # Verificar que todos los sockets están suscritos
    sockets.each_with_index do |socket, i|
      Hauyna::WebSocket::Channel.subscribed?(channel, socket).should be_true
    end
  end
end 