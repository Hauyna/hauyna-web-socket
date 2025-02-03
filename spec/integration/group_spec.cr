require "../spec_helper"

describe "Group Management" do
  it "handles group operations" do
    socket1 = MockWebSocket.new
    socket2 = MockWebSocket.new
    group_name = "test_group"

    # Registrar sockets
    Hauyna::WebSocket::ConnectionManager.register(socket1, "user1")
    Hauyna::WebSocket::ConnectionManager.register(socket2, "user2")

    # Agregar usuarios al grupo
    Hauyna::WebSocket::ConnectionManager.add_to_group("user1", group_name)
    Hauyna::WebSocket::ConnectionManager.add_to_group("user2", group_name)

    # Verificar miembros del grupo
    members = Hauyna::WebSocket::ConnectionManager.get_group_members(group_name)
    members.should contain("user1")
    members.should contain("user2")

    # Enviar mensaje al grupo
    message = {"type" => "group_message", "content" => "hello"}.to_json
    Hauyna::WebSocket::ConnectionManager.send_to_group(group_name, message)

    # Verificar que ambos sockets recibieron el mensaje
    socket1.received_messages.should contain(message)
    socket2.received_messages.should contain(message)

    # Remover un usuario del grupo
    Hauyna::WebSocket::ConnectionManager.remove_from_group("user1", group_name)
    Hauyna::WebSocket::ConnectionManager.get_group_members(group_name).should_not contain("user1")
  end
end 