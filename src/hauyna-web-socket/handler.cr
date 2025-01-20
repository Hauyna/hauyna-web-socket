require "json"
require "http/web_socket"
require "./connection_manager"

module Hauyna
  module WebSocket
    class Handler
      property on_open : Proc(HTTP::WebSocket, Hash(String, JSON::Any), Nil)?
      property on_message : Proc(HTTP::WebSocket, String, Nil)?
      property on_close : Proc(HTTP::WebSocket, Nil)?
      property on_ping : Proc(HTTP::WebSocket, String, Nil)?
      property on_pong : Proc(HTTP::WebSocket, String, Nil)?
      property extract_identifier : Proc(HTTP::WebSocket, Hash(String, JSON::Any), String?)?

      def initialize(
        @on_open = nil,
        @on_message = nil,
        @on_close = nil,
        @on_ping = nil,
        @on_pong = nil,
        @extract_identifier = nil
      )
      end

      def call(socket : HTTP::WebSocket, params : Hash(String, JSON::Any))
        if identifier_proc = @extract_identifier
          identifier = identifier_proc.call(socket, params)
          ConnectionManager.register(socket, identifier) if identifier
        end

        if open_proc = @on_open
          open_proc.call(socket, params)
        end

        socket.on_message do |message|
          if message_proc = @on_message
            message_proc.call(socket, message)
          end
        end

        socket.on_close do
          if close_proc = @on_close
            close_proc.call(socket)
          end
          ConnectionManager.unregister(socket)
        end

        socket.on_ping do |message|
          if ping_proc = @on_ping
            ping_proc.call(socket, message)
          end
        end

        socket.on_pong do |message|
          if pong_proc = @on_pong
            pong_proc.call(socket, message)
          end
        end
      end
    end
  end
end
