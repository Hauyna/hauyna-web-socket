require "http"

module Hauyna
  module WebSocket
    class Router
      property websocket_routes : Array(WebSocketRoute)

      def initialize
        @websocket_routes = [] of WebSocketRoute
      end

      def websocket(path : String, handler : Handler)
        @websocket_routes << WebSocketRoute.new(path, handler)
      end

      def call(context : HTTP::Server::Context) : Bool
        request = context.request
        path = request.path

        websocket_route = @websocket_routes.find { |r| r.match?(path) }

        if websocket_route &&
           request.headers["Upgrade"] == "websocket" &&
           request.headers["Connection"].includes?("Upgrade")
          begin
            handler = websocket_route.handler

            ws_handler = HTTP::WebSocketHandler.new do |socket, ctx|
              handler.on_open(socket)
              socket.on_message do |message|
                handler.on_message(socket, message)
              end
              socket.on_close do
                handler.on_close(socket)
              end
              socket.on_ping do |message|
                handler.on_ping(socket, message)
              end
              socket.on_pong do |message|
                handler.on_pong(socket, message)
              end
            end

            ws_handler.call(context)
            return true
          rescue ex : Exception
            context.response.status_code = 500
            context.response.print "Error: #{ex.message}"
            return true
          end
        else
          return false
        end
      end
    end
  end
end
