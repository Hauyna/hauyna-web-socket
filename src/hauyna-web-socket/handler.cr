require "json"
require "http/web_socket"
require "./connection_manager"
require "./heartbeat"

module Hauyna
  module WebSocket
    class Handler
      property on_open : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_message : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_close : Proc(HTTP::WebSocket, Nil)?
      property on_ping : Proc(HTTP::WebSocket, String, Nil)?
      property on_pong : Proc(HTTP::WebSocket, String, Nil)?
      property extract_identifier : Proc(HTTP::WebSocket, JSON::Any, String?)?
      property heartbeat : Heartbeat?

      def initialize(
        @on_open = nil,
        @on_message = nil,
        @on_close = nil,
        @on_ping = nil,
        @on_pong = nil,
        @extract_identifier = nil,
        heartbeat_interval : Time::Span? = nil,
        heartbeat_timeout : Time::Span? = nil
      )
        if heartbeat_interval
          @heartbeat = Heartbeat.new(
            interval: heartbeat_interval,
            timeout: heartbeat_timeout || heartbeat_interval * 2
          )
        end
      end

      def call(socket : HTTP::WebSocket, params : Hash(String, JSON::Any))
        json_params = JSON::Any.new(params)
        
        if identifier_proc = @extract_identifier
          identifier = identifier_proc.call(socket, json_params)
          ConnectionManager.register(socket, identifier) if identifier
        end

        if open_proc = @on_open
          open_proc.call(socket, json_params)
        end

        socket.on_message do |message|
          if message_proc = @on_message
            begin
              parsed_message = JSON.parse(message)
              message_proc.call(socket, parsed_message)
            rescue JSON::ParseException
              message_proc.call(socket, JSON::Any.new(message))
            end
          end
        end

        socket.on_close do
          if close_proc = @on_close
            close_proc.call(socket)
          end
          ConnectionManager.unregister(socket)
          if heartbeat = @heartbeat
            heartbeat.cleanup(socket)
          end
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

        if heartbeat = @heartbeat
          heartbeat.start(socket)
          
          socket.on_pong do
            heartbeat.record_pong(socket)
          end
        end
      end
    end
  end
end
