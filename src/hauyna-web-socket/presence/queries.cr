module Hauyna
  module WebSocket
    class Presence
      def self.list(channel : String? = nil, group : String? = nil) : Hash(String, Hash(String, JSON::Any))
        @@presence.select { |_, meta| meta["channel"]? == JSON::Any.new(channel) }
      end

      def self.list_by(criteria : Hash(String, String)) : Hash(String, Hash(String, JSON::Any))
        @@presence.select do |_, meta|
          criteria.all? do |key, value|
            meta[key]? == JSON::Any.new(value)
          end
        end
      end

      def self.present_in?(identifier : String, context : Hash(String, String)) : Bool
        if metadata = @@presence[identifier]?
          context.all? do |key, value|
            metadata[key]? == JSON::Any.new(value)
          end
        else
          false
        end
      end

      def self.count_by(context : Hash(String, String)? = nil) : Int32
        if context
          list_by(context).size
        else
          @@presence.size
        end
      end

      def self.in_channel(channel : String) : Array(String)
        @@presence.select { |_, meta|
          meta["channel"]? == JSON::Any.new(channel)
        }.keys
      end

      def self.in_group(group : String) : Array(String)
        @@presence.select { |_, meta|
          meta["group"]? == JSON::Any.new(group)
        }.keys
      end

      def self.get_state(identifier : String) : Hash(String, JSON::Any)?
        @@presence[identifier]?
      end

      def self.get_presence(identifier : String) : Hash(String, JSON::Any)?
        @@presence[identifier]?
      end

      def self.present?(identifier : String) : Bool
        @@presence.has_key?(identifier)
      end

      def self.count : Int32
        @@presence.size
      end
    end
  end
end 