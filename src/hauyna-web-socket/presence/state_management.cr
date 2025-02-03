module Hauyna
  module WebSocket
    module Presence
      # Definir estados válidos como constantes
      STATES = {
        ONLINE:      "online",
        OFFLINE:     "offline",
        ERROR:       "error",
        CONNECTING:  "connecting",
        DISCONNECTED: "disconnected"
      }

      @@presence = {} of String => Hash(String, JSON::Any)
      @@mutex = Mutex.new
      @@operation_channel = ::Channel(PresenceOperation).new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          process_operation(operation)
        end
      end

      private def self.process_operation(operation : PresenceOperation)
        begin
          case operation.type
          when :track
            data = operation.data.as(PresenceOperation::TrackData)
            safe_track(data[:identifier], data[:metadata])
          when :untrack
            data = operation.data.as(PresenceOperation::UntrackData)
            safe_untrack(data[:identifier])
          when :update
            data = operation.data.as(PresenceOperation::UpdateData)
            safe_update(data[:identifier], data[:metadata])
          end
        rescue ex : TypeCastError | JSON::ParseException
          Log.error { "Error procesando operación de presencia: #{ex.message}" }
          if identifier = operation.data.try(&.[:identifier]?.as?(String))
            set_error_state(identifier, ex)
          end
        end
      end

      def self.track(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata: metadata,
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
            metadata: metadata,
          }.as(PresenceOperation::UpdateData))
        )
      end

      private def self.safe_track(identifier : String, metadata : Hash(String, JSON::Any))
        begin
          @@mutex.synchronize do
            metadata = metadata.merge({
              "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
              "state" => JSON::Any.new(STATES[:ONLINE])
            })

            @@presence[identifier] = {
              "metadata" => JSON::Any.new(metadata.to_json),
              "state" => JSON::Any.new(STATES[:ONLINE])
            }
          end
          notify_presence_change
        rescue ex
          handle_presence_error(identifier, ex)
          raise ex # Re-lanzar para que process_operation lo maneje
        end
      end

      private def self.safe_untrack(identifier : String)
        @@mutex.synchronize do
          @@presence.delete(identifier)
        end
        notify_presence_change
      end

      private def self.safe_update(identifier : String, metadata : Hash(String, JSON::Any))
        @@mutex.synchronize do
          if current = @@presence[identifier]?
            begin
              # Intentar parsear la metadata para verificar que es válida
              if metadata["metadata"]?
                JSON.parse(metadata["metadata"].as_s)
              end

              current_metadata = JSON.parse(current["metadata"].as_s).as_h
              updated_metadata = current_metadata.merge(metadata)

              @@presence[identifier] = {
                "metadata" => JSON::Any.new(updated_metadata.to_json),
                "state" => JSON::Any.new(metadata["state"]?.try(&.as_s) || current["state"].as_s)
              }
            rescue ex : JSON::ParseException
              # Si hay un error de parsing, lanzar la excepción para que process_operation la maneje
              raise ex
            end
          end
        end
        notify_presence_change
      end

      def self.list : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence.dup
        end
      end

      def self.list_by_channel(channel : String) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          presence_data = {} of String => Hash(String, JSON::Any)
          
          @@presence.each do |identifier, data|
            if metadata = data["metadata"]?.try(&.as_s)
              begin
                parsed_metadata = JSON.parse(metadata).as_h
                if parsed_metadata["channel"]?.try(&.as_s) == channel
                  presence_data[identifier] = data
                end
              rescue ex
                handle_presence_error(identifier, ex)
              end
            end
          end
          
          presence_data
        end
      end

      private def self.set_error_state(identifier : String, error : Exception)
        @@mutex.synchronize do
          if current = @@presence[identifier]?
            begin
              current_metadata = JSON.parse(current["metadata"].as_s).as_h
            rescue
              current_metadata = {} of String => JSON::Any
            end

            error_metadata = current_metadata.merge({
              "state" => JSON::Any.new(STATES[:ERROR]),
              "error_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
              "error_message" => JSON::Any.new(error.message || "Unknown error")
            })

            @@presence[identifier] = {
              "metadata" => JSON::Any.new(error_metadata.to_json),
              "state" => JSON::Any.new(STATES[:ERROR])
            }
          end
        end
        notify_presence_change
      end

      private def self.handle_presence_error(identifier : String, error : Exception)
        set_error_state(identifier, error)
      end

      private def self.notify_presence_change
        spawn do
          begin
            presence_state = @@mutex.synchronize { @@presence.dup }
            Channel.broadcast_to("presence", {
              "type" => JSON::Any.new("presence_update"),
              "state" => JSON::Any.new(presence_state.to_json)
            })
          rescue ex
            Log.error { "Error al notificar cambio de presencia: #{ex.message}" }
          end
        end
      end
    end
  end
end
