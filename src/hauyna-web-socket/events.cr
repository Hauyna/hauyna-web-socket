require "json"
require "http/web_socket"
require "./connection_manager"

module Hauyna
  module WebSocket
    module Events
      alias EventCallback = Proc(HTTP::WebSocket, Hash(String, JSON::Any), Nil)
      @@event_handlers = {} of String => Array(EventCallback)

      def self.on(event : String, &block : EventCallback)
        @@event_handlers[event] ||= [] of EventCallback
        @@event_handlers[event] << block
      end

      def self.trigger_event(event : String, socket : HTTP::WebSocket, data : Hash(String, JSON::Any))
        if handlers = @@event_handlers[event]?
          handlers.each do |handler|
            begin
              handler.call(socket, data)
            rescue ex
              puts "Error en el manejador de eventos: #{ex.message}"
            end
          end
        end
      end

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
