require "../spec_helper"

describe "Presence Integration" do
  it "tracks user presence" do
    socket = MockWebSocket.new
    channel = "test_channel"
    
    # Registrar y suscribir usuario
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    sleep 0.1.seconds
    
    # Suscribir con metadata completa
    metadata = {
      "user_id" => JSON::Any.new("test_user"),
      "status" => JSON::Any.new("online"),
      "channel" => JSON::Any.new(channel),
      "custom_data" => JSON::Any.new("test_value")
    }

    Hauyna::WebSocket::Channel.subscribe(
      channel,
      socket,
      "test_user",
      metadata
    )

    sleep 0.1.seconds

    # Verificar datos de presencia
    presence_data = Hauyna::WebSocket::Channel.presence_data(channel)
    presence_data["test_user"]?.should_not be_nil
    
    if user_data = presence_data["test_user"]?
      parsed = JSON.parse(user_data.as_s)
      parsed["user_id"].should eq("test_user")
      
      # Verificar estado directamente desde la metadata
      if metadata = parsed["metadata"]?
        metadata_hash = JSON.parse(metadata.as_s).as_h
        metadata_hash["state"]?.try(&.as_s).should eq(Hauyna::WebSocket::Presence::STATES[:ONLINE])
        metadata_hash["custom_data"]?.try(&.as_s).should eq("test_value")
        metadata_hash["channel"]?.try(&.as_s).should eq(channel)
      end
    end

    # Simular desconexión y esperar a que se procese
    Hauyna::WebSocket::Channel.unsubscribe(channel, socket)
    Hauyna::WebSocket::ConnectionManager.cleanup_socket(socket)
    sleep 0.2.seconds # Aumentamos el tiempo de espera para asegurar el procesamiento

    # Verificar que el usuario ya no está presente
    updated_presence = Hauyna::WebSocket::Channel.presence_data(channel)
    updated_presence["test_user"]?.should be_nil
  end

  it "handles presence errors gracefully" do
    socket = MockWebSocket.new
    channel = "test_channel"
    
    # Registrar primero el usuario
    Hauyna::WebSocket::ConnectionManager.register(socket, "test_user")
    sleep 0.1.seconds

    # Suscribir con metadata válida primero
    valid_metadata = {
      "user_id" => JSON::Any.new("test_user"),
      "channel" => JSON::Any.new(channel),
      "state" => JSON::Any.new(Hauyna::WebSocket::Presence::STATES[:ONLINE])
    }

    Hauyna::WebSocket::Channel.subscribe(
      channel,
      socket,
      "test_user",
      valid_metadata
    )

    sleep 0.1.seconds

    # Crear metadata que causará un error de JSON
    invalid_metadata = {
      "metadata" => JSON::Any.new("{ invalid json }"),
      "channel" => JSON::Any.new(channel),
      "state" => JSON::Any.new(Hauyna::WebSocket::Presence::STATES[:ONLINE])
    }

    # Actualizar directamente para forzar el error de parsing
    Hauyna::WebSocket::Presence.update("test_user", invalid_metadata)
    sleep 0.2.seconds # Dar tiempo para que se procese el error

    # Verificar que se manejó el error usando el método get_presence
    presence_data = Hauyna::WebSocket::Presence.get_presence("test_user")
    presence_data.should_not be_nil
    
    if presence_data
      presence_data["state"].as_s.should eq(Hauyna::WebSocket::Presence::STATES[:ERROR])
      if metadata = presence_data["metadata"]?
        metadata_hash = JSON.parse(metadata.as_s).as_h
        metadata_hash["state"]?.try(&.as_s).should eq(Hauyna::WebSocket::Presence::STATES[:ERROR])
        metadata_hash["error_message"]?.should_not be_nil
        metadata_hash["error_at"]?.should_not be_nil
      end
    end
  end
end 