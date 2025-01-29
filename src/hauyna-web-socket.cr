require "./hauyna-web-socket/channel/channel"
require "./hauyna-web-socket/connection_manager/connection_manager"
require "./hauyna-web-socket/events/events"
require "./hauyna-web-socket/handler/handler"
require "./hauyna-web-socket/presence/presence"
require "./hauyna-web-socket/router/router"
require "./hauyna-web-socket/logging"
require "./hauyna-web-socket/message_validator"
require "./hauyna-web-socket/heartbeat"
require "./hauyna-web-socket/error_handler"

module Hauyna
  module WebSocket
    VERSION = "1.0.1"

    # Alias para facilitar el uso de ConnectionState
    alias ConnectionState = ConnectionManager::ConnectionState
  end
end
