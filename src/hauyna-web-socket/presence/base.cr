module Hauyna
  module WebSocket
    module Presence
      @@presence = {} of String => Hash(String, JSON::Any)
      @@operation_channel = ::Channel(PresenceOperation).new
      @@mutex = Mutex.new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          process_operation(operation)
        end
      end

      # API pública
      def self.track(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata:   metadata,
          }.as(PresenceOperation::TrackData))
        )
      end

      def self.untrack(identifier : String)
        @@operation_channel.send(
          PresenceOperation.new(:untrack, {
            identifier: identifier,
          }.as(PresenceOperation::UntrackData))
        )
      end

      def self.update(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:update, {
            identifier: identifier,
            metadata:   metadata,
          }.as(PresenceOperation::UpdateData))
        )
      end

      private def self.process_operation(operation : PresenceOperation)
        @@mutex.synchronize do
          case operation.type
          when :track
            internal_track(operation.identifier, operation.metadata)
          when :untrack
            internal_untrack(operation.identifier)
          when :update
            internal_update(operation.identifier, operation.metadata)
          end
        end
      end
    end
  end
end
