module Hauyna
  module WebSocket
    class Handler
      property on_open_callback : Proc(HTTP::WebSocket, Nil)?
      property on_message_callback : Proc(HTTP::WebSocket, String, Nil)?
      property on_close_callback : Proc(HTTP::WebSocket, Nil)?
      property on_ping_callback : Proc(HTTP::WebSocket, String, Nil)?
      property on_pong_callback : Proc(HTTP::WebSocket, String, Nil)?

      def initialize(
        on_open : Proc(HTTP::WebSocket, Nil)? = nil,
        on_message : Proc(HTTP::WebSocket, String, Nil)? = nil,
        on_close : Proc(HTTP::WebSocket, Nil)? = nil,
        on_ping : Proc(HTTP::WebSocket, String, Nil)? = nil,
        on_pong : Proc(HTTP::WebSocket, String, Nil)? = nil,
      )
        @on_open_callback = on_open
        @on_message_callback = on_message
        @on_close_callback = on_close
        @on_ping_callback = on_ping
        @on_pong_callback = on_pong
      end

      def on_open(socket : HTTP::WebSocket)
        if @on_open_callback
          open_callback = @on_open_callback.as(Proc(HTTP::WebSocket, Nil))
          open_callback.call(socket)
        end
      end

      def on_message(socket : HTTP::WebSocket, message : String)
        if @on_message_callback
          message_callback = @on_message_callback.as(Proc(HTTP::WebSocket, String, Nil))
          message_callback.call(socket, message)
        end
      end

      def on_close(socket : HTTP::WebSocket)
        if @on_close_callback
          close_callback = @on_close_callback.as(Proc(HTTP::WebSocket, Nil))
          close_callback.call(socket)
        end
      end

      def on_ping(socket : HTTP::WebSocket, message : String)
        if @on_ping_callback
          ping_callback = @on_ping_callback.as(Proc(HTTP::WebSocket, String, Nil))
          ping_callback.call(socket, message)
        end
      end

      def on_pong(socket : HTTP::WebSocket, message : String)
        if @on_pong_callback
          pong_callback = @on_pong_callback.as(Proc(HTTP::WebSocket, String, Nil))
          pong_callback.call(socket, message)
        end
      end
    end
  end
end
