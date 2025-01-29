module Hauyna
  module WebSocket
    class Handler
      private def setup_connection(socket : HTTP::WebSocket, params : Hash(String, JSON::Any))
        json_params = JSON::Any.new(params)

        if identifier_proc = @extract_identifier
          identifier = identifier_proc.call(socket, json_params)
          return unless identifier

          ConnectionManager.register(socket, identifier)

          # Auto-suscribir al canal principal si existe
          if default_channel = params["channel"]?.try(&.as_s)
            Channel.subscribe(default_channel, socket, identifier, {
              "user_id" => JSON::Any.new(identifier),
            })
          end
        end
      end

      private def cleanup_connection(socket : HTTP::WebSocket)
        if identifier = ConnectionManager.get_identifier(socket)
          Presence.untrack(identifier)
        end
        Channel.cleanup_socket(socket)
        ConnectionManager.unregister(socket)
        if heartbeat = @heartbeat
          heartbeat.cleanup(socket)
        end
      end
    end
  end
end 