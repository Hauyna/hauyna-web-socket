require "./presence_operation"

module Hauyna
  module WebSocket
    module Presence
      class PresenceManager
        CHANNEL_BUFFER_SIZE = 100
        
        # Estados válidos para la presencia
        STATES = {
          ONLINE:      "online",
          OFFLINE:     "offline",
          ERROR:       "error",
          CONNECTING:  "connecting",
          DISCONNECTED: "disconnected"
        }

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
          case operation.type
          when :track
            data = operation.data.as(PresenceOperation::TrackData)
            @mutex.synchronize do
              validated_metadata = validate_metadata(data[:metadata])
              presence_data = {
                "state" => JSON::Any.new(validated_metadata["state"].as_s),
                "status" => JSON::Any.new(validated_metadata["status"].as_s),
                "metadata" => JSON::Any.new(validated_metadata.to_json)
              }
              @presence[data[:identifier]] = presence_data
            end
          when :update
            data = operation.data.as(PresenceOperation::UpdateData)
            @mutex.synchronize do
              validated_metadata = validate_metadata(data[:metadata])
              @presence[data[:identifier]] = {
                "state" => JSON::Any.new(validated_metadata["state"].as_s),
                "status" => JSON::Any.new(validated_metadata["status"].as_s),
                "metadata" => JSON::Any.new(validated_metadata.to_json)
              }
            end
          when :untrack
            data = operation.data.as(PresenceOperation::UntrackData)
            @mutex.synchronize do
              @presence.delete(data[:identifier])
            end
          end
        end

        private def validate_metadata(metadata : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
          begin
            # Validate each metadata field that could contain JSON
            metadata.each do |key, value|
              if value.as_s?
                begin
                  # Try to parse any string value as JSON to catch invalid JSON
                  JSON.parse(value.as_s)
                rescue ex
                  # If any field contains invalid JSON, raise an error
                  raise Exception.new("Invalid JSON in field '#{key}': #{ex.message}")
                end
              end
            end

            # If all validations pass
            metadata["updated_at"] = JSON::Any.new(Time.utc.to_s)
            metadata["state"] = JSON::Any.new(STATES[:ONLINE])
            # Ensure status is present, default to online if not provided
            metadata["status"] = JSON::Any.new(metadata["status"]?.try(&.as_s) || STATES[:ONLINE])
            metadata
          rescue ex
            # If validation fails, return error state with details
            error_metadata = {
              "state" => JSON::Any.new(STATES[:ERROR]),
              "status" => JSON::Any.new(metadata["status"]?.try(&.as_s) || STATES[:ERROR]),
              "error_message" => JSON::Any.new(ex.message || "Invalid metadata format"),
              "error_at" => JSON::Any.new(Time.utc.to_s)
            }

            # Try to preserve original metadata safely
            begin
              error_metadata["original_metadata"] = JSON::Any.new(metadata.to_json)
            rescue
              error_metadata["original_metadata"] = JSON::Any.new("{}")
            end

            error_metadata
          end
        end
      end
    end
  end
end 