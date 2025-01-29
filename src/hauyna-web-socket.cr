require "./hauyna-web-socket/channel/mod"
require "./hauyna-web-socket/connection_manager/mod"
require "./hauyna-web-socket/events/mod"
require "./hauyna-web-socket/handler/mod"
require "./hauyna-web-socket/presence/mod"
require "./hauyna-web-socket/router/mod"
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
