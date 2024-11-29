require "json"

module Hauyna
  module WebSocket
    module Events
      @@event_handlers = {} of String => Proc(HTTP::WebSocket, JSON::Any, Nil)

      def self.on(event_name : String, &block : Proc(HTTP::WebSocket, JSON::Any, Nil))
        @@event_handlers[event_name] = block
      end

      def self.trigger_event(event_name : String, socket : HTTP::WebSocket, data : JSON::Any)
        handler = @@event_handlers[event_name]
        if handler
          handler.call(socket, data)
        else
          puts "No handler registered for event '#{event_name}'"
        end
      end
    end
  end
end
