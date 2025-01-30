module Hauyna
  module WebSocket
    module ConnectionManager
      def self.register(socket : HTTP::WebSocket, identifier : String)
        @@operation_channel.send(
          ConnectionOperation.new(:register, {
            socket:     socket,
            identifier: identifier,
          }.as(ConnectionOperation::RegisterData))
        )
      end

      def self.unregister(socket : HTTP::WebSocket)
        @@operation_channel.send(
          ConnectionOperation.new(:unregister, {
            socket: socket,
          }.as(ConnectionOperation::UnregisterData))
        )
      end

      def self.broadcast(message : String)
        @@operation_channel.send(
          ConnectionOperation.new(:broadcast, {
            message: message,
          }.as(ConnectionOperation::BroadcastData))
        )
      end

      def self.add_to_group(identifier : String, group_name : String)
        @@operation_channel.send(
          ConnectionOperation.new(:add_to_group, {
            identifier: identifier,
            group_name: group_name,
          }.as(ConnectionOperation::GroupData))
        )
      end

      # Métodos de utilidad
      def self.get_socket(identifier : String) : HTTP::WebSocket?
        @@mutex.synchronize do
          @@connections[identifier]?
        end
      end

      def self.send_to_one(identifier : String, message : String)
        socket = @@mutex.synchronize do
          @@connections[identifier]?
        end

        if socket
          begin
            socket.send(message)
          rescue
            cleanup_socket(socket)
          end
        end
      end

      def self.send_to_many(identifiers : Array(String), message : String)
        # Obtener sockets bajo el lock
        sockets = @@mutex.synchronize do
          identifiers.compact_map { |id| @@connections[id]? }
        end

        # Enviar mensajes fuera del lock
        sockets.each do |socket|
          begin
            socket.send(message)
          rescue
            cleanup_socket(socket)
          end
        end
      end

      def self.send_to_group(group_name : String, message : String)
        # Obtener miembros e identificadores bajo el lock
        sockets = @@mutex.synchronize do
          members = @@groups[group_name]?.try(&.dup) || Set(String).new
          members.compact_map { |id| @@connections[id]? }
        end

        # Enviar mensajes fuera del lock
        sockets.each do |socket|
          begin
            socket.send(message)
          rescue
            cleanup_socket(socket)
          end
        end
      end

      def self.clear
        @@mutex.synchronize do
          @@connections.clear
          @@groups.clear
          @@socket_to_identifier.clear
          @@connection_states.clear
          @@state_timestamps.clear
          @@retry_policies.clear
          @@retry_attempts.clear
        end
      end

      def self.get_identifier(socket : HTTP::WebSocket) : String?
        @@mutex.synchronize do
          @@socket_to_identifier[socket]?
        end
      end

      def self.all_connections : Array(HTTP::WebSocket)
        @@mutex.synchronize do
          @@connections.values.to_a
        end
      end

      def self.count : Int32
        @@mutex.synchronize do
          @@connections.size
        end
      end

      def self.get_connection_state(socket : HTTP::WebSocket) : ConnectionState?
        @@mutex.synchronize do
          @@connection_states[socket]?
        end
      end

      def self.get_state_timestamp(socket : HTTP::WebSocket) : Time?
        @@mutex.synchronize do
          @@state_timestamps[socket]?
        end
      end

      def self.connections_in_state(state : ConnectionState) : Array(HTTP::WebSocket)
        @@mutex.synchronize do
          @@connection_states.select { |_, s| s == state }.keys
        end
      end

      def self.cleanup_socket(socket : HTTP::WebSocket)
        @@operation_channel.send(
          ConnectionOperation.new(:unregister, {
            socket: socket,
          }.as(ConnectionOperation::UnregisterData))
        )
      end
    end
  end
end
