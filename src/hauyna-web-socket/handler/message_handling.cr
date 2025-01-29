module Hauyna
  module WebSocket
    class Handler
      private def handle_channel_message(socket : HTTP::WebSocket, parsed_message : JSON::Any)
        if channel = parsed_message["channel"]?.try(&.as_s)
          if identifier = ConnectionManager.get_identifier(socket)
            if Channel.subscribed?(channel, socket)
              if content = parsed_message["content"]?
                # Convertir el contenido al formato correcto
                message_to_send = case content
                when .as_s?
                  content.as_s
                when .as_h?
                  content.as_h.transform_values { |v| v.as(JSON::Any) }
                else
                  content.to_json
                end
                Channel.broadcast_to(channel, message_to_send)
              end
            end
          end
        end
      end

      private def handle_channel_subscription(socket : HTTP::WebSocket, parsed_message : JSON::Any)
        case parsed_message["type"]?.try(&.as_s)
        when "subscribe_channel"
          if channel = parsed_message["channel"]?.try(&.as_s)
            if identifier = ConnectionManager.get_identifier(socket)
              metadata = parsed_message["metadata"]?.try(&.as_h) || {} of String => JSON::Any
              Channel.subscribe(channel, socket, identifier, metadata)
            end
          end
        when "unsubscribe_channel"
          if channel = parsed_message["channel"]?.try(&.as_s)
            Channel.unsubscribe(channel, socket)
          end
        end
      end
    end
  end
end 