module Hauyna
  module WebSocket
    class Presence
      private def self.internal_track(identifier, metadata)
        @@presence[identifier] = metadata
        spawn do
          broadcast_presence_change("join", identifier, metadata)
        end
      end

      private def self.internal_untrack(identifier)
        if metadata = @@presence.delete(identifier)
          spawn do
            broadcast_presence_change("leave", identifier, metadata)
          end
        end
      end

      private def self.internal_update(identifier, metadata)
        if @@presence[identifier]?
          @@presence[identifier] = metadata
          spawn do
            broadcast_presence_change("update", identifier, metadata)
          end
        end
      end

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