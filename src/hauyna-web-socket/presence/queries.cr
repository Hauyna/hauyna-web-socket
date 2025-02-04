require "./presence_manager"

module Hauyna
  module WebSocket
    module Presence
      extend self

      def get(identifier : String) : Hash(String, JSON::Any)?
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence[identifier]?.try(&.dup)
        end
      end

      # Alias para mantener compatibilidad
      def get_presence(identifier : String) : Hash(String, JSON::Any)?
        get(identifier)
      end

      def list : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.dup
        end
      end

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

      def list_by(criteria : Hash(String, String)) : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.select do |_, data|
            criteria.all? do |key, value|
              data[key]?.try(&.as_s) == value
            end
          end.dup
        end
      end

      def list_by(metadata_key : String, metadata_value : String) : Hash(String, Hash(String, JSON::Any))
        PresenceManager.instance.mutex.synchronize do
          list_by({metadata_key => metadata_value}).dup
        end
      end

      def get_metadata(identifier : String) : Hash(String, JSON::Any)?
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence[identifier]?.try(&.dup)
        end
      end

      def count : Int32
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.size
        end
      end

      def count_by_channel(channel : String) : Int32
        PresenceManager.instance.mutex.synchronize do
          PresenceManager.instance.presence.count do |_, data|
            data["channel"]?.try(&.as_s) == channel
          end
        end
      end

      def get_state(identifier : String) : Hash(String, JSON::Any)?
        get(identifier)
      end
    end
  end
end
