require "./presence_manager"

module Hauyna
  module WebSocket
    module Presence
      extend self

      def track(identifier : String, metadata : Hash(String, JSON::Any))
        return unless PresenceManager.instance.processor_fiber?
        
        PresenceManager.instance.operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata:   metadata,
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
        
        PresenceManager.instance.operation_channel.send(
          PresenceOperation.new(:update, {
            identifier: identifier,
            metadata:   metadata,
          }.as(PresenceOperation::UpdateData))
        )
      end

      def cleanup_all
        PresenceManager.instance.cleanup
      end

      def list : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.dup
        end
      end
    end
  end
end
