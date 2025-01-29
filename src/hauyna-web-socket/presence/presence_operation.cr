module Hauyna
  module WebSocket
    class Presence
      private class PresenceOperation
        # Definir los tipos específicos para cada operación
        alias TrackData = NamedTuple(
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias UntrackData = NamedTuple(
          identifier: String
        )

        alias UpdateData = NamedTuple(
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias OperationData = TrackData | UntrackData | UpdateData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end
    end
  end
end 