module Hauyna
  module WebSocket
    module Presence
      private def self.broadcast_presence_change(event : String, identifier : String, metadata : Hash(String, JSON::Any))
        message = {
          type:     "presence_change",
          event:    event,
          user:     identifier,
          metadata: metadata,
        }.to_json

        spawn do
          ConnectionManager.broadcast(message)
          if channel = metadata["channel"]?.try(&.as_s)
            Channel.broadcast_to(channel, message)
          end
        end
      end
    end
  end
end 