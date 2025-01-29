module Hauyna
  module WebSocket
    module ConnectionManager
      # Definir el enum al inicio para que esté disponible para otras partes del módulo
      enum ConnectionState
        Connected
        Disconnected
        Reconnecting
        Error
        Idle
      end

      private VALID_TRANSITIONS = {
        ConnectionState::Connected => [ConnectionState::Idle, ConnectionState::Disconnected, ConnectionState::Error],
        ConnectionState::Idle => [ConnectionState::Connected, ConnectionState::Disconnected, ConnectionState::Error],
        ConnectionState::Disconnected => [ConnectionState::Reconnecting, ConnectionState::Error],
        ConnectionState::Reconnecting => [ConnectionState::Connected, ConnectionState::Error],
        ConnectionState::Error => [ConnectionState::Reconnecting]
      }

      # Canal para operaciones de estado
      @@state_operation_channel = ::Channel(StateOperation).new

      # Procesador de operaciones de estado
      spawn do
        loop do
          operation = @@state_operation_channel.receive
          process_state_operation(operation)
        end
      end

      private def self.process_state_operation(operation : StateOperation)
        @@mutex.synchronize do
          socket = operation.socket
          new_state = operation.new_state
          current_state = @@connection_states[socket]?

          if current_state.nil? || valid_transition?(current_state, new_state)
            old_state = current_state
            @@connection_states[socket] = new_state
            @@state_timestamps[socket] = Time.local

            # Notificar cambio de estado fuera del lock
            spawn do
              notify_state_hooks(socket, old_state, new_state)
            end

            # Manejar reintentos si es necesario
            if new_state == ConnectionState::Error
              spawn do
                handle_retry(socket)
              end
            end
          end
        end
      end

      private def self.handle_retry(socket : HTTP::WebSocket)
        return unless policy = @@retry_policies[socket]?
        
        @@mutex.synchronize do
          attempts = @@retry_attempts[socket] ||= 0
          return if attempts >= policy.max_attempts

          @@retry_attempts[socket] += 1
          current_attempt = @@retry_attempts[socket]
          delay = policy.calculate_delay(current_attempt)
        end

        # Programar el reintento fuera del lock
        spawn do
          sleep delay
          
          # Verificar el estado actual antes de intentar reconectar
          @@mutex.synchronize do
            current_state = @@connection_states[socket]?
            if current_state == ConnectionState::Error
              @@state_operation_channel.send(
                StateOperation.new(socket, ConnectionState::Reconnecting)
              )
            end
          end
        end
      end

      private def self.notify_state_hooks(socket, old_state, new_state)
        if hooks = @@state_hooks[:state_change]?
          hooks.each do |hook|
            begin
              hook.call(socket, old_state || new_state, new_state)
            rescue ex
              Log.error { "Error en hook de estado: #{ex.message}" }
            end
          end
        end
      end

      def self.set_connection_state(socket : HTTP::WebSocket, new_state : ConnectionState)
        @@state_operation_channel.send(
          StateOperation.new(socket, new_state)
        )
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

      def self.on_state_change(&block : HTTP::WebSocket, ConnectionState?, ConnectionState -> Nil)
        @@state_hooks[:state_change] ||= [] of Proc(HTTP::WebSocket, ConnectionState?, ConnectionState, Nil)
        @@mutex.synchronize do
          @@state_hooks[:state_change] << block
        end
      end

      private def self.valid_transition?(from : ConnectionState, to : ConnectionState) : Bool
        return true if from == to
        VALID_TRANSITIONS[from]?.try(&.includes?(to)) || false
      end

      def self.add_valid_transition(from : ConnectionState, to : ConnectionState)
        VALID_TRANSITIONS[from] ||= [] of ConnectionState
        VALID_TRANSITIONS[from] << to unless VALID_TRANSITIONS[from].includes?(to)
      end

      private def self.internal_set_state(socket, state)
        @@connection_states[socket] = state
        @@state_timestamps[socket] = Time.local
        
        if identifier = get_identifier(socket)
          state_message = {
            "type" => JSON::Any.new("connection_state"),
            "user" => JSON::Any.new(identifier),
            "state" => JSON::Any.new(state.to_s),
            "timestamp" => JSON::Any.new(Time.local.to_unix_ms.to_s)
          }
          
          begin
            socket.send(state_message.to_json)
          rescue
            @@connection_states[socket] = ConnectionState::Error
          end
        end
      end
    end
  end
end 