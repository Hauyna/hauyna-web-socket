module Hauyna
  module WebSocket
    module ConnectionManager
      private class StateOperation
        getter socket : HTTP::WebSocket
        getter new_state : ConnectionState

        def initialize(@socket, @new_state)
        end
      end
    end
  end
end 