module Hauyna
  module WebSocket
    class Handler
      private def handle_message(socket : HTTP::WebSocket, message : String)
        return unless message_proc = @on_message

        begin
          parsed_message = JSON.parse(message)
          MessageValidator.validate_message(parsed_message)

          handle_channel_subscription(socket, parsed_message)
          
          if parsed_message["type"]?.try(&.as_s) == "channel_message"
            handle_channel_message(socket, parsed_message)
          else
            message_proc.call(socket, parsed_message)
          end
        rescue ex : JSON::ParseException | MessageValidator::ValidationError
          ErrorHandler.handle(socket, ex)
        rescue ex
          ErrorHandler.handle(socket, ex)
          ConnectionManager.set_connection_state(socket, ConnectionState::Error)
        end
      end
    end
  end
end 