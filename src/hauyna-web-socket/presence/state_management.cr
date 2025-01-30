module Hauyna
  module WebSocket
    module Presence
      private def self.process_operation(operation : PresenceOperation)
        @@mutex.synchronize do
          case operation.type
          when :track
            data = operation.data.as(PresenceOperation::TrackData)
            internal_track(data[:identifier], data[:metadata])
          when :untrack
            data = operation.data.as(PresenceOperation::UntrackData)
            internal_untrack(data[:identifier])
          when :update
            data = operation.data.as(PresenceOperation::UpdateData)
            internal_update(data[:identifier], data[:metadata])
          end
        end
      end

      private def self.internal_track(identifier : String, metadata : Hash(String, JSON::Any))
        # Ya estamos dentro del mutex desde process_operation
        metadata = metadata.merge({
          "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
        })

        @@presence[identifier] = {
          "metadata" => JSON::Any.new(metadata.to_json),
          "state"    => JSON::Any.new("online"),
        }

        spawn do
          broadcast_presence_change("join", identifier, metadata)
        end
      end

      private def self.internal_untrack(identifier : String)
        # Ya estamos dentro del mutex desde process_operation
        if metadata = @@presence[identifier]?.try(&.["metadata"]?.try(&.as_h))
          @@presence.delete(identifier)
          spawn do
            broadcast_presence_change("leave", identifier, metadata)
          end
        end
      end

      private def self.internal_update(identifier : String, metadata : Hash(String, JSON::Any))
        # Ya estamos dentro del mutex desde process_operation
        if current_data = @@presence[identifier]?
          current_metadata = current_data["metadata"]?.try(&.as_h) || {} of String => JSON::Any
          updated_metadata = current_metadata.merge(metadata)

          @@presence[identifier] = {
            "metadata" => JSON::Any.new(updated_metadata.to_json),
            "state"    => current_data["state"]? || JSON::Any.new("online"),
          }

          spawn do
            broadcast_presence_change("update", identifier, updated_metadata)
          end
        end
      end
    end
  end
end
