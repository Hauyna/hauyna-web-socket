require "http"
require "json"
require "./handler"

module Hauyna
  module WebSocket
    class Router
      def initialize
        @routes = {} of String => Handler
      end

      def websocket(path : String, handler : Handler)
        @routes[path] = handler
      end

      def call(context : HTTP::Server::Context) : Bool
        request = context.request
        response = context.response

        if handler = match_route(request.path)
          # Verificar si es una solicitud de WebSocket
          if upgrade_websocket?(request)
            # Extraer parámetros de la query
            params = extract_params(request)
            
            # Crear un WebSocketHandler para manejar el handshake
            ws_handler = HTTP::WebSocketHandler.new do |ws, ctx|
              handler.call(ws, params)
            end

            # Procesar la solicitud WebSocket
            ws_handler.call(context)
            return true
          end
        end

        false
      end

      private def match_route(path : String) : Handler?
        @routes[path]?
      end

      private def upgrade_websocket?(request : HTTP::Request) : Bool
        return false unless upgrade = request.headers["Upgrade"]?
        return false unless upgrade.compare("websocket", case_insensitive: true) == 0
        return false unless connection = request.headers["Connection"]?
        return false unless connection.compare("Upgrade", case_insensitive: true) == 0
        true
      end

      private def extract_params(request : HTTP::Request) : Hash(String, JSON::Any)
        params = Hash(String, JSON::Any).new

        if query = request.query
          query.split('&').each do |param|
            if param.includes?('=')
              key, value = param.split('=', 2)
              params[URI.decode_www_form(key)] = JSON::Any.new(URI.decode_www_form(value))
            end
          end
        end

        params
      end
    end
  end
end
