module Hauyna
  module WebSocket
    class Heartbeat
      property interval : Time::Span
      property timeout : Time::Span

      def initialize(@interval = 30.seconds, @timeout = 60.seconds)
        @last_pong = {} of HTTP::WebSocket => Time
      end

      def start(socket : HTTP::WebSocket)
        spawn do
          loop do
            sleep @interval

            # Enviar ping
            begin
              socket.ping
              check_timeout(socket)
            rescue ex
              # 1000 es el código para cierre normal
              socket.close(1000)
              break
            end
          end
        end
      end

      private def check_timeout(socket)
        if last = @last_pong[socket]?
          if Time.local - last > @timeout
            # 1001 es el código para "Going Away"
            socket.close(1001, "Heartbeat timeout")
          end
        end
      end

      def record_pong(socket : HTTP::WebSocket)
        @last_pong[socket] = Time.local
      end

      def cleanup(socket : HTTP::WebSocket)
        @last_pong.delete(socket)
      end
    end
  end
end
