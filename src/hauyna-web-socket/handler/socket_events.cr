module Hauyna
  module WebSocket
    class Handler
      private def setup_socket_events(socket : HTTP::WebSocket)
        # Los timeouts se manejarán a través del heartbeat
        setup_message_handler(socket)
        setup_close_handler(socket)
        setup_ping_handler(socket)
        setup_pong_handler(socket)
        setup_heartbeat(socket)
      end

      private def setup_message_handler(socket : HTTP::WebSocket)
        socket.on_message do |message|
          ConnectionManager.set_connection_state(socket, ConnectionState::Connected)
          handle_message(socket, message)
        end
      end

      private def setup_close_handler(socket : HTTP::WebSocket)
        socket.on_close do
          ConnectionManager.set_connection_state(socket, ConnectionState::Disconnected)
          if close_proc = @on_close
            close_proc.call(socket)
          end
          cleanup_connection(socket)
        end
      end

      private def setup_ping_handler(socket : HTTP::WebSocket)
        socket.on_ping do |message|
          if ping_proc = @on_ping
            ping_proc.call(socket, message)
          end
        end
      end

      private def setup_pong_handler(socket : HTTP::WebSocket)
        socket.on_pong do |message|
          if pong_proc = @on_pong
            pong_proc.call(socket, message)
          end
          if heartbeat = @heartbeat
            heartbeat.record_pong(socket)
          end
        end
      end

      private def setup_heartbeat(socket : HTTP::WebSocket)
        if heartbeat = @heartbeat
          begin
            heartbeat.start(socket)
          rescue ex
            ErrorHandler.handle(socket, ex)
            ConnectionManager.set_connection_state(socket, ConnectionState::Error)
          end
        end
      end
    end
  end
end
