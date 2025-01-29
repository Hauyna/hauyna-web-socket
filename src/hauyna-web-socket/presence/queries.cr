module Hauyna
  module WebSocket
    module Presence
      # Métodos de consulta protegidos por mutex
      def self.list : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence.dup
        end
      end

      def self.list_by_channel(channel : String) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence.select do |_, data|
            data["channel"]?.try(&.as_s) == channel
          end
        end
      end

      def self.list_by(criteria : Hash(String, String)) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence.select do |_, data|
            criteria.all? do |key, value|
              data[key]?.try(&.as_s) == value
            end
          end.dup
        end
      end

      def self.list_by(metadata_key : String, metadata_value : String) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          list_by({metadata_key => metadata_value}).dup
        end
      end

      def self.get_metadata(identifier : String) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@presence[identifier]?.try(&.dup)
        end
      end

      def self.present?(identifier : String) : Bool
        @@mutex.synchronize do
          @@presence.has_key?(identifier)
        end
      end

      def self.present_in?(channel : String, identifier : String) : Bool
        @@mutex.synchronize do
          if data = @@presence[identifier]?
            data["channel"]?.try(&.as_s) == channel
          else
            false
          end
        end
      end

      def self.in_channel(channel : String) : Array(String)
        @@mutex.synchronize do
          @@presence.select do |_, data|
            data["channel"]?.try(&.as_s) == channel
          end.keys.to_a
        end
      end

      def self.in_group(group : String) : Array(String)
        @@mutex.synchronize do
          @@presence.select do |_, data|
            data["group"]?.try(&.as_s) == group
          end.keys.to_a
        end
      end

      def self.count_by(context : Hash(String, String)? = nil) : Int32
        @@mutex.synchronize do
          if context
            @@presence.count do |_, data|
              context.all? do |key, value|
                data[key]?.try(&.as_s) == value
              end
            end
          else
            @@presence.size
          end
        end
      end

      def self.count : Int32
        @@mutex.synchronize do
          @@presence.size
        end
      end

      def self.count_by_channel(channel : String) : Int32
        @@mutex.synchronize do
          @@presence.count do |_, data|
            data["channel"]?.try(&.as_s) == channel
          end
        end
      end

      def self.get_presence(identifier : String) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@presence[identifier]?.try(&.dup)
        end
      end

      # Alias para mantener compatibilidad
      def self.get_state(identifier : String) : Hash(String, JSON::Any)?
        get_presence(identifier)
      end
    end
  end
end 