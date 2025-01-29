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
    end
  end
end 