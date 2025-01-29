module Hauyna
  module WebSocket
    class Handler
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
        @write_timeout : Int32 = 30
      )
        if heartbeat_interval
          @heartbeat = Heartbeat.new(
            interval: heartbeat_interval,
            timeout: heartbeat_timeout || heartbeat_interval * 2
          )
        end
      end
    end
  end
end 