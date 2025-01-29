module Hauyna
  module WebSocket
    module ConnectionManager
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

      def self.on_state_change(&block : HTTP::WebSocket, ConnectionState, ConnectionState -> Nil)
        @@state_hooks[:state_change] ||= [] of Proc(HTTP::WebSocket, ConnectionState, ConnectionState, Nil)
        @@state_hooks[:state_change] << block
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