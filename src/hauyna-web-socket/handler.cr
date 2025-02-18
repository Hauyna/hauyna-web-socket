require "json"
require "http/web_socket"

require "./handler/*"
require "./batch_processing/batch_processor"

module Hauyna
  module WebSocket
    class Handler
      # Declaramos las variables de instancia
      property on_open : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_message : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_close : Proc(HTTP::WebSocket, Nil)?
      property on_ping : Proc(HTTP::WebSocket, String, Nil)?
      property on_pong : Proc(HTTP::WebSocket, String, Nil)?
      property extract_identifier : Proc(HTTP::WebSocket, JSON::Any, String)?
      property heartbeat : Heartbeat?
      property read_timeout : Int32
      property write_timeout : Int32
      
      # Inicializamos batch_processor como opcional
      @batch_processor : BatchProcessing::Processor? = nil

      def initialize(
        @on_open = nil,
        @on_message = nil,
        @on_close = nil,
        @on_ping = nil,
        @on_pong = nil,
        @extract_identifier = nil,
        heartbeat_interval : Time::Span? = nil,
        heartbeat_timeout : Time::Span? = nil,
        @read_timeout : Int32 = 30,
        @write_timeout : Int32 = 30,
        batch_config : BatchProcessing::Config? = nil
      )
        # Actualizamos el batch_processor si se proporciona una configuración
        if config = batch_config
          @batch_processor = BatchProcessing::Processor.new(config)
        end

        if heartbeat_interval
          @heartbeat = Heartbeat.new(
            interval: heartbeat_interval,
            timeout: heartbeat_timeout || heartbeat_interval * 2
          )
        end
      end

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

      def on_message(socket : HTTP::WebSocket, message : JSON::Any)
        if processor = @batch_processor
          processor.add(message) do |operation|
            if callback = @on_message
              callback.call(socket, operation)
            end
          end
        elsif callback = @on_message
          callback.call(socket, message)
        end
      end

      private def setup_connection(socket : HTTP::WebSocket, params : Hash(String, JSON::Any))
        # Setup connection logic here
      end

      private def setup_socket_events(socket : HTTP::WebSocket)
        # Setup socket events logic here
      end
    end
  end
end
