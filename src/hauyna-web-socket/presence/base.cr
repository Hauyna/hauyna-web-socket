require "./presence_manager"

module Hauyna
  module WebSocket
    module Presence
      extend self

      def track(identifier : String, metadata : Hash(String, JSON::Any))
        return unless PresenceManager.instance.processor_fiber?
        
        validated_metadata = validate_metadata(metadata)
        PresenceManager.instance.operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata:   validated_metadata,
          }.as(PresenceOperation::TrackData))
        )
      end

      def untrack(identifier : String)
        return unless PresenceManager.instance.processor_fiber?
        
        PresenceManager.instance.operation_channel.send(
          PresenceOperation.new(:untrack, {
            identifier: identifier,
          }.as(PresenceOperation::UntrackData))
        )
      end

      def update(identifier : String, metadata : Hash(String, JSON::Any))
        return unless PresenceManager.instance.processor_fiber?
        
        validated_metadata = validate_metadata(metadata)
        PresenceManager.instance.operation_channel.send(
          PresenceOperation.new(:update, {
            identifier: identifier,
            metadata:   validated_metadata,
          }.as(PresenceOperation::UpdateData))
        )
      end

      def cleanup_all
        PresenceManager.instance.cleanup
      end

      def list : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          presence_data = {} of String => Hash(String, JSON::Any)
          PresenceManager.instance.presence.each do |identifier, data|
            if metadata_str = data["metadata"]?.try(&.as_s)
              begin
                parsed_metadata = JSON.parse(metadata_str).as_h
                validated_metadata = validate_metadata(parsed_metadata)
                presence_data[identifier] = {
                  "metadata" => JSON::Any.new(validated_metadata.to_json),
                  "status" => validated_metadata["status"]? || JSON::Any.new("online")
                }
              rescue ex
                handle_presence_error(identifier, ex)
              end
            else
              # Si no hay metadatos, crear un registro con valores por defecto
              presence_data[identifier] = {
                "metadata" => JSON::Any.new({"status" => "online"}.to_json),
                "status" => JSON::Any.new("online")
              }
            end
          end
          presence_data
        end
      end

      private def handle_presence_error(identifier : String, error : Exception)
        set_error_state(identifier, error)
      end

      private def set_error_state(identifier : String, error : Exception)
        PresenceManager.instance.mutex.synchronize do
          if current = PresenceManager.instance.presence[identifier]?
            metadata = begin
              JSON.parse(current["metadata"].as_s).as_h
            rescue
              {} of String => JSON::Any
            end
            metadata["status"] = JSON::Any.new("error")
            metadata["error"] = JSON::Any.new(error.message || "Unknown error")
            current["metadata"] = JSON::Any.new(metadata.to_json)
            PresenceManager.instance.presence[identifier] = current
          end
        end
      end
    end
  end
end
