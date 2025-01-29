module Hauyna
  module WebSocket
    module ConnectionManager
      private def self.internal_register(socket, identifier)
        @@connections[identifier] = socket
        @@socket_to_identifier[socket] = identifier
        
        # Agregar estado inicial
        @@connection_states[socket] = ConnectionState::Connected
        @@state_timestamps[socket] = Time.local

        # Notificar el nuevo estado
        notify_state_change(socket, nil, ConnectionState::Connected)
      end

      private def self.internal_unregister(socket)
        if identifier = @@socket_to_identifier[socket]?
          @@connections.delete(identifier)
          @@socket_to_identifier.delete(socket)
          @@connection_states.delete(socket)
          @@state_timestamps.delete(socket)
          @@retry_policies.delete(socket)
          @@retry_attempts.delete(socket)
          @@groups.each do |_, members|
            members.delete(identifier)
          end

          # Notificar desconexión
          notify_state_change(socket, ConnectionState::Connected, ConnectionState::Disconnected)
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

      private def self.notify_state_change(socket, old_state, new_state)
        if hooks = @@state_hooks[:state_change]?
          hooks.each do |hook|
            begin
              hook.call(socket, old_state || new_state, new_state)
            rescue ex
              puts "Error en hook de estado: #{ex.message}"
            end
          end
        end
      end

      def self.handle_reconnection(socket : HTTP::WebSocket, old_socket : HTTP::WebSocket)
        if identifier = get_identifier(old_socket)
          # Transferir identificador al nuevo socket
          @@socket_to_identifier.delete(old_socket)
          @@socket_to_identifier[socket] = identifier
          @@connections[identifier] = socket

          # Transferir estado y timestamps
          if old_state = @@connection_states[old_socket]?
            @@connection_states.delete(old_socket)
            @@connection_states[socket] = ConnectionState::Connected
          end

          # Transferir política de reintentos si existe
          if policy = @@retry_policies[old_socket]?
            @@retry_policies.delete(old_socket)
            @@retry_policies[socket] = policy
            @@retry_attempts[socket] = 0
          end

          # Notificar reconexión
          notify_state_change(socket, ConnectionState::Disconnected, ConnectionState::Connected)
        end
      end

      def self.set_connection_state(socket : HTTP::WebSocket, new_state : ConnectionState) : Bool
        current_state = @@connection_states[socket]?
        
        unless current_state
          internal_set_state(socket, new_state)
          return true
        end

        unless valid_transition?(current_state, new_state)
          return false
        end

        notify_state_change(socket, current_state, new_state)
        internal_set_state(socket, new_state)

        if new_state == ConnectionState::Error
          handle_retry(socket)
        elsif new_state == ConnectionState::Connected
          @@retry_attempts[socket] = 0
        end

        true
      end
    end
  end
end 