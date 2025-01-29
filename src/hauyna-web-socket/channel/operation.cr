module Hauyna
  module WebSocket
    class Channel
      private class ChannelOperation
        # Define aliases at module level
        alias SubscribeData = NamedTuple(
          channel: String,
          socket: HTTP::WebSocket,
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias UnsubscribeData = NamedTuple(
          channel: String,
          socket: HTTP::WebSocket
        )

        alias BroadcastData = NamedTuple(
          channel: String,
          message: String | Hash(String, JSON::Any)
        )

        alias OperationData = SubscribeData | UnsubscribeData | BroadcastData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end
    end
  end
end 