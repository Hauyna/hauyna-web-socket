require "http/web_socket"

module Hauyna
  module WebSocket
    module ConnectionManager
      private class ConnectionOperation
        # Definir los tipos específicos para cada operación
        alias RegisterData = NamedTuple(
          socket: HTTP::WebSocket,
          identifier: String
        )

        alias UnregisterData = NamedTuple(
          socket: HTTP::WebSocket
        )

        alias BroadcastData = NamedTuple(
          message: String
        )

        alias GroupData = NamedTuple(
          identifier: String,
          group_name: String
        )

        alias OperationData = RegisterData | UnregisterData | BroadcastData | GroupData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end

      @@connections = {} of String => HTTP::WebSocket
      @@socket_to_identifier = {} of HTTP::WebSocket => String
      @@groups = {} of String => Set(String)
      @@operation_channel = ::Channel(ConnectionOperation).new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          case operation.type
          when :register
            data = operation.data.as(ConnectionOperation::RegisterData)
            internal_register(data[:socket], data[:identifier])
          when :unregister
            data = operation.data.as(ConnectionOperation::UnregisterData)
            internal_unregister(data[:socket])
          when :broadcast
            data = operation.data.as(ConnectionOperation::BroadcastData)
            internal_broadcast(data[:message])
          when :add_to_group
            data = operation.data.as(ConnectionOperation::GroupData)
            internal_add_to_group(data[:identifier], data[:group_name])
          end
        end
      end

      private def self.internal_register(socket, identifier)
        @@connections[identifier] = socket
        @@socket_to_identifier[socket] = identifier
      end

      private def self.internal_unregister(socket)
        if identifier = @@socket_to_identifier[socket]?
          @@connections.delete(identifier)
          @@socket_to_identifier.delete(socket)
          @@groups.each do |_, members|
            members.delete(identifier)
          end
        end
      end

      private def self.internal_broadcast(message)
        @@connections.each_value do |socket|
          spawn do
            begin
              socket.send(message)
            rescue
              @@operation_channel.send(
                ConnectionOperation.new(:unregister, {
                  socket: socket
                }.as(ConnectionOperation::UnregisterData))
              )
            end
          end
        end
      end

      private def self.internal_add_to_group(identifier, group_name)
        @@groups[group_name] ||= Set(String).new
        @@groups[group_name].add(identifier)
      end

      # API pública
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

      # Obtiene el socket asociado a un identificador
      def self.get_socket(identifier : String) : HTTP::WebSocket?
        @@connections[identifier]
      end

      # Añade un usuario a un grupo específico
      def self.remove_from_group(identifier : String, group_name : String)
        if group = @@groups[group_name]?
          group.delete(identifier)
          @@groups.delete(group_name) if group.empty?
        end
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
        # Obtener miembros del grupo bajo el lock
        members = @@groups[group_name]?.try(&.dup) || Set(String).new

        # Enviar mensajes fuera del lock
        members.each do |identifier|
          send_to_one(identifier, message)
        end
      end

      def self.get_group_members(group_name : String) : Set(String)
        members = @@groups[group_name]?.try(&.dup) || Set(String).new
        puts "Miembros del grupo #{group_name}: #{members.inspect}"
        members
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

      # Obtener todos los grupos a los que pertenece un usuario
      def self.get_user_groups(identifier : String) : Array(String)
        groups = [] of String
        @@groups.each do |group_name, members|
          if members.includes?(identifier)
            groups << group_name
          end
        end
        groups
      end

      def self.is_in_group?(identifier : String, group_name : String) : Bool
        if group = @@groups[group_name]?
          group.includes?(identifier)
        else
          false
        end
      end
    end
  end
end
