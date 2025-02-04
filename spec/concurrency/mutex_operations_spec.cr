require "../spec_helper"

describe "Concurrency Operations" do
  before_each do
    # Reset channel state before each test
    Hauyna::WebSocket::Channel.cleanup_all
    Hauyna::WebSocket::Presence.cleanup_all if Hauyna::WebSocket::Presence.responds_to?(:cleanup_all)
  end

  it "handles concurrent channel operations safely" do
    channel = "test_channel"
    sockets = Array.new(5) { MockWebSocket.new }
    user_ids = (1..5).map { |i| "user#{i}" }
    
    # Register all sockets
    sockets.zip(user_ids).each do |socket, user_id|
      Hauyna::WebSocket::ConnectionManager.register(socket, user_id)
    end
    sleep 0.1.seconds

    # Concurrent subscriptions
    sockets.zip(user_ids).each do |socket, user_id|
      spawn do
        Hauyna::WebSocket::Channel.subscribe(
          channel,
          socket,
          user_id,
          {"user_id" => JSON::Any.new(user_id)}
        )
      end
    end
    
    sleep 0.5.seconds # Wait for operations to complete
    
    # Verify all subscriptions succeeded
    count = Hauyna::WebSocket::Channel.subscription_count(channel)
    count.should eq(5)
    
    # Verify each socket is subscribed exactly once
    sockets.each do |socket|
      Hauyna::WebSocket::Channel.subscribed?(channel, socket).should be_true
    end
    
    # Concurrent broadcasts
    10.times do |i|
      spawn do
        message = {"type" => "broadcast", "content" => "msg#{i}"}.to_json
        Hauyna::WebSocket::Channel.broadcast_to(channel, message)
      end
    end
    
    sleep 0.5.seconds # Wait for broadcasts
    
    # Verify all sockets received messages
    sockets.each do |socket|
      socket.received_messages.size.should be > 0
    end
  end

  it "handles concurrent presence operations safely" do
    user_ids = (1..5).map { |i| "user#{i}" }
    
    # Concurrent presence tracking
    user_ids.each do |user_id|
      spawn do
        metadata = {
          "user_id" => JSON::Any.new(user_id),
          "status" => JSON::Any.new("online")
        }
        Hauyna::WebSocket::Presence.track(user_id, metadata)
      end
    end
    
    sleep 0.5.seconds # Wait for operations
    
    # Verify presence count
    presence_list = Hauyna::WebSocket::Presence.list
    presence_list.size.should eq(5)
    
    # Concurrent presence updates
    user_ids.each do |user_id|
      spawn do
        metadata = {
          "user_id" => JSON::Any.new(user_id),
          "status" => JSON::Any.new("away")
        }
        Hauyna::WebSocket::Presence.update(user_id, metadata)
      end
    end
    
    sleep 0.5.seconds # Wait for updates
    
    # Verify updates were applied
    presence_list = Hauyna::WebSocket::Presence.list
    presence_list.each do |presence_entry|
      identifier, metadata = presence_entry
      metadata["status"].as_s.should eq("away")
    end
  end

  it "handles concurrent connection management safely" do
    sockets = Array.new(5) { MockWebSocket.new }
    user_ids = (1..5).map { |i| "user#{i}" }
    
    # Concurrent registrations
    sockets.zip(user_ids).each do |socket, user_id|
      spawn do
        Hauyna::WebSocket::ConnectionManager.register(socket, user_id)
      end
    end
    
    sleep 0.5.seconds # Wait for registrations
    
    # Verify all connections are registered
    sockets.all? { |socket| Hauyna::WebSocket::ConnectionManager.get_identifier(socket) != nil }.should be_true
    
    # Concurrent disconnections
    sockets.zip(user_ids).each do |socket, user_id|
      spawn do
        Hauyna::WebSocket::ConnectionManager.unregister(socket)
      end
    end
    
    sleep 0.5.seconds # Wait for disconnections
    
    # Verify all connections are closed
    sockets.all? { |socket| Hauyna::WebSocket::ConnectionManager.get_identifier(socket) == nil }.should be_true
  end
end 