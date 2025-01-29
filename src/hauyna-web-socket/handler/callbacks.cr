module Hauyna
  module WebSocket
    class Handler
      property on_open : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_message : Proc(HTTP::WebSocket, JSON::Any, Nil)?
      property on_close : Proc(HTTP::WebSocket, Nil)?
      property on_ping : Proc(HTTP::WebSocket, String, Nil)?
      property on_pong : Proc(HTTP::WebSocket, String, Nil)?
      property extract_identifier : Proc(HTTP::WebSocket, JSON::Any, String)?
      property heartbeat : Heartbeat?
    end
  end
end
