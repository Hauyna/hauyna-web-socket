module Hauyna
  module WebSocket
    class Presence
      @@presence = {} of String => Hash(String, JSON::Any)
      @@operation_channel = ::Channel(PresenceOperation).new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
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

      def self.track(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata: metadata
          }.as(PresenceOperation::TrackData))
        )
      end

      def self.untrack(identifier : String)
        @@operation_channel.send(
          PresenceOperation.new(:untrack, {
            identifier: identifier
          }.as(PresenceOperation::UntrackData))
        )
      end

      def self.update(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:update, {
            identifier: identifier,
            metadata: metadata
          }.as(PresenceOperation::UpdateData))
        )
      end
    end
  end
end 