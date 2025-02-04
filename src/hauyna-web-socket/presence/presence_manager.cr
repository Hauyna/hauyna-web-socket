require "./presence_operation"

module Hauyna
  module WebSocket
    module Presence
      class PresenceManager
        CHANNEL_BUFFER_SIZE = 100

        class_property instance : PresenceManager { new }
        
        getter operation_channel : ::Channel(PresenceOperation)
        getter mutex : Mutex
        getter presence : Hash(String, Hash(String, JSON::Any))
        getter processor_fiber : Fiber?

        def processor_fiber?
          !@processor_fiber.nil?
        end

        private def initialize
          @operation_channel = ::Channel(PresenceOperation).new(CHANNEL_BUFFER_SIZE)
          @mutex = Mutex.new
          @presence = {} of String => Hash(String, JSON::Any)
          @processor_fiber = nil
          start_processor
        end

        private def start_processor
          return if @processor_fiber

          @processor_fiber = spawn do
            loop do
              begin
                operation = @operation_channel.receive
                process_operation(operation)
              rescue ex : Exception
                Log.error { "Error processing presence operation: #{ex.message}" }
              end
            end
          end
        end

        def cleanup
          @mutex.synchronize do
            @presence.clear
            if channel = @operation_channel
              channel.close
              @operation_channel = ::Channel(PresenceOperation).new(CHANNEL_BUFFER_SIZE)
            end
            @processor_fiber = nil
            start_processor
          end
        end

        private def process_operation(operation : PresenceOperation)
          @mutex.synchronize do
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
        rescue ex : Exception
          Log.error { "Error processing operation #{operation.type}: #{ex.message}" }
        end

        private def internal_track(identifier : String, metadata : Hash(String, JSON::Any))
          processed_metadata = metadata.merge({
            "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
            "state" => JSON::Any.new(STATES[:ONLINE])
          })

          @presence[identifier] = {
            "metadata" => JSON::Any.new(processed_metadata.to_json),
            "status" => metadata["status"]? || JSON::Any.new(STATES[:ONLINE]),
            "state" => JSON::Any.new(STATES[:ONLINE])
          }
        end

        private def internal_untrack(identifier : String)
          @presence.delete(identifier)
        end

        private def internal_update(identifier : String, metadata : Hash(String, JSON::Any))
          if current = @presence[identifier]?
            current_metadata = JSON.parse(current["metadata"].as_s).as_h
            updated_metadata = current_metadata.merge(metadata)

            @presence[identifier] = {
              "metadata" => JSON::Any.new(updated_metadata.to_json),
              "state" => JSON::Any.new(metadata["state"]?.try(&.as_s) || current["state"].as_s)
            }
          end
        end
      end
    end
  end
end 