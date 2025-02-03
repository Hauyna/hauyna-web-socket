module Hauyna
  module WebSocket
    class Heartbeat
      property interval : Time::Span
      property timeout : Time::Span

      def initialize(@interval : Time::Span = 30.seconds, @timeout : Time::Span = 60.seconds)
        @sockets = {} of HTTP::WebSocket => Time
        @mutex = Mutex.new
        
        spawn do
          loop do
            check_timeouts
            sleep @interval
          end
        end
      end

      def start(socket : HTTP::WebSocket)
        register(socket)
      end

      private def check_timeouts
        now = Time.local
        sockets_to_close = [] of HTTP::WebSocket

        @mutex.synchronize do
          @sockets.each do |socket, last_pong|
            if now - last_pong > @timeout
              sockets_to_close << socket
            end
          end
        end

        sockets_to_close.each do |socket|
          socket.close(4000, "Heartbeat timeout")
        end
      end

      def register(socket : HTTP::WebSocket)
        @mutex.synchronize do
          @sockets[socket] = Time.local
        end
      end

      # Mantener ambos métodos para compatibilidad
      def record_pong(socket : HTTP::WebSocket)
        handle_pong(socket, "")
      end

      def handle_pong(socket : HTTP::WebSocket, message : String)
        @mutex.synchronize do
          @sockets[socket] = Time.local
          # Actualizar estado si es necesario
          if ConnectionManager.get_connection_state(socket) == ConnectionState::Idle
            ConnectionManager.set_connection_state(socket, ConnectionState::Connected)
          end
        end
      end

      def cleanup(socket : HTTP::WebSocket)
        @mutex.synchronize do
          @sockets.delete(socket)
        end
      end
    end
  end
end
