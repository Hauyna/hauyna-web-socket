require "http/web_socket"
require "json"

require "./hauyna-web-socket/error_handler"
require "./hauyna-web-socket/message_validator"
require "./hauyna-web-socket/heartbeat"
require "./hauyna-web-socket/batch_processing/batch_processor"

require "./hauyna-web-socket/connection_manager/connection_manager"
require "./hauyna-web-socket/channel/channel"
require "./hauyna-web-socket/events/events"
require "./hauyna-web-socket/handler/handler"
require "./hauyna-web-socket/presence/presence"
require "./hauyna-web-socket/router/router"

module Hauyna
  module WebSocket
    VERSION = "1.0.0"

    # Alias para facilitar el uso de ConnectionState
    alias ConnectionState = ConnectionManager::ConnectionState
    
    # Alias para facilitar el uso del procesamiento por lotes
    alias BatchConfig = BatchProcessing::Config
    alias BatchProcessor = BatchProcessing::Processor
  end
end
