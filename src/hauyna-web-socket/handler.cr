require "json"
require "http/web_socket"

require "./handler/*"

module Hauyna
  module WebSocket
    class Handler
      def call(socket : HTTP::WebSocket, params : Hash(String, JSON::Any))
        begin
          setup_connection(socket, params)

          if open_proc = @on_open
            begin
              open_proc.call(socket, JSON::Any.new(params))
            rescue ex
              ErrorHandler.handle(socket, ex)
            end
          end

          setup_socket_events(socket)
        rescue ex
          ErrorHandler.handle(socket, ex)
          ConnectionManager.set_connection_state(socket, ConnectionState::Error)
          socket.close
        end
      end
    end
  end
end
