module Hauyna
  module WebSocket
    module Events
      def self.broadcast(content : String)
        ConnectionManager.broadcast(content)
      end

      def self.send_to_one(identifier : String, content : String)
        ConnectionManager.send_to_one(identifier, content)
      end

      def self.send_to_many(identifiers : Array(String), content : String)
        ConnectionManager.send_to_many(identifiers, content)
      end

      def self.send_to_group(group_name : String, content : String)
        ConnectionManager.send_to_group(group_name, content)
      end
    end
  end
end
