module Hauyna
  module WebSocket
    module ConnectionManager
      def self.register(socket : HTTP::WebSocket, identifier : String)
        @@operation_channel.send(
          ConnectionOperation.new(:register, {
            socket: socket,
            identifier: identifier
          }.as(ConnectionOperation::RegisterData))
        )
      end

      def self.unregister(socket : HTTP::WebSocket)
        @@operation_channel.send(
          ConnectionOperation.new(:unregister, {
            socket: socket
          }.as(ConnectionOperation::UnregisterData))
        )
      end

      def self.broadcast(message : String)
        @@operation_channel.send(
          ConnectionOperation.new(:broadcast, {
            message: message
          }.as(ConnectionOperation::BroadcastData))
        )
      end

      def self.add_to_group(identifier : String, group_name : String)
        @@operation_channel.send(
          ConnectionOperation.new(:add_to_group, {
            identifier: identifier,
            group_name: group_name
          }.as(ConnectionOperation::GroupData))
        )
      end

      # Métodos de utilidad
      def self.get_socket(identifier : String) : HTTP::WebSocket?
        @@connections[identifier]
      end

      def self.send_to_one(identifier : String, message : String)
        if socket = @@connections[identifier]?
          begin
            socket.send(message)
          rescue
          end
        end
      end

      def self.send_to_many(identifiers : Array(String), message : String)
        identifiers.each do |identifier|
          send_to_one(identifier, message)
        end
      end

      def self.send_to_group(group_name : String, message : String)
        members = @@groups[group_name]?.try(&.dup) || Set(String).new
        members.each do |identifier|
          send_to_one(identifier, message)
        end
      end

      def self.clear
        @@connections.clear
        @@groups.clear
        @@socket_to_identifier.clear
      end

      def self.get_identifier(socket : HTTP::WebSocket) : String?
        @@socket_to_identifier[socket]
      end

      def self.all_connections : Array(HTTP::WebSocket)
        @@connections.values
      end

      def self.count : Int32
        @@connections.size
      end

      def self.get_connection_state(socket : HTTP::WebSocket) : ConnectionState?
        @@connection_states[socket]?
      end

      def self.get_state_timestamp(socket : HTTP::WebSocket) : Time?
        @@state_timestamps[socket]?
      end

      def self.connections_in_state(state : ConnectionState) : Array(HTTP::WebSocket)
        @@connection_states.select { |_, s| s == state }.keys
      end
    end
  end
end 