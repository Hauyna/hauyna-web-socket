require "./presence_manager"

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

      extend self

      def list_by_channel(channel : String) : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          presence_data = {} of String => Hash(String, JSON::Any)
          
          PresenceManager.instance.presence.each do |identifier, data|
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

      def present?(identifier : String) : Bool
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.has_key?(identifier)
        end
      end

      def present_in?(channel : String, identifier : String) : Bool
        PresenceManager.instance.mutex.synchronize do
          if data = PresenceManager.instance.presence[identifier]?
            data["channel"]?.try(&.as_s) == channel
          else
            false
          end
        end
      end

      def in_channel(channel : String) : Array(String)
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.select do |_, data|
            data["channel"]?.try(&.as_s) == channel
          end.keys.to_a
        end
      end

      def in_group(group : String) : Array(String)
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.select do |_, data|
            data["group"]?.try(&.as_s) == group
          end.keys.to_a
        end
      end

      def count_by(context : Hash(String, String)? = nil) : Int32
        PresenceManager.instance.mutex.synchronize do
          if context
            PresenceManager.instance.presence.count do |_, data|
              context.all? do |key, value|
                if metadata = data["metadata"]?.try(&.as_s)
                  begin
                    parsed_metadata = JSON.parse(metadata).as_h
                    parsed_metadata[key]?.try(&.as_s) == value
                  rescue
                    false
                  end
                else
                  false
                end
              end
            end
          else
            PresenceManager.instance.presence.size
          end
        end
      end

      private def handle_presence_error(identifier : String, error : Exception)
        set_error_state(identifier, error)
      end

      private def set_error_state(identifier : String, error : Exception)
        PresenceManager.instance.mutex.synchronize do
          if current = PresenceManager.instance.presence[identifier]?
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

            PresenceManager.instance.presence[identifier] = {
              "metadata" => JSON::Any.new(error_metadata.to_json),
              "state" => JSON::Any.new(STATES[:ERROR])
            }
          end
        end
        notify_presence_change
      end

      private def notify_presence_change
        spawn do
          begin
            presence_state = PresenceManager.instance.mutex.synchronize { PresenceManager.instance.presence.dup }
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
