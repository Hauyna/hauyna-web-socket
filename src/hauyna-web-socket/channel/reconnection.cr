module Hauyna
  module WebSocket
    class Channel
      def self.handle_reconnection(socket : HTTP::WebSocket, old_socket : HTTP::WebSocket)
        # Obtener todas las suscripciones del socket anterior
        subscriptions_to_transfer = [] of Tuple(String, Subscription)

        @@channels.each do |channel, subs|
          if subscription = subs.find { |s| s.socket == old_socket }
            subscriptions_to_transfer << {channel, subscription}
          end
        end

        # Transferir cada suscripción al nuevo socket
        subscriptions_to_transfer.each do |channel, old_subscription|
          # Eliminar la suscripción antigua
          if subs = @@channels[channel]?
            subs.delete(old_subscription)

            # Crear y agregar la nueva suscripción
            new_subscription = Subscription.new(
              socket: socket,
              identifier: old_subscription.identifier,
              metadata: old_subscription.metadata
            )
            subs.add(new_subscription)

            # Notificar la reconexión
            event_message = {
              "type"     => JSON::Any.new("channel_event"),
              "event"    => JSON::Any.new("subscription_reconnected"),
              "channel"  => JSON::Any.new(channel),
              "user"     => JSON::Any.new(old_subscription.identifier),
              "metadata" => JSON::Any.new(old_subscription.metadata.to_json),
            }

            # Broadcast el evento de reconexión
            spawn do
              internal_broadcast(channel, event_message)
            end
          end
        end

        # Actualizar presencia si es necesario
        if !subscriptions_to_transfer.empty?
          if first_sub = subscriptions_to_transfer.first?
            Presence.update(
              first_sub[1].identifier,
              first_sub[1].metadata.merge({
                "reconnected" => JSON::Any.new(Time.local.to_unix_ms.to_s)
              })
            )
          end
        end
      end

      def self.cleanup_socket(socket : HTTP::WebSocket)
        channels_to_cleanup = [] of String
        subscriptions_to_remove = [] of Tuple(String, Subscription)

        @@channels.each do |channel, subs|
          if subscription = subs.find { |s| s.socket == socket }
            channels_to_cleanup << channel
            subscriptions_to_remove << {channel, subscription}
          end
        end

        # Procesar las limpiezas fuera del lock principal
        subscriptions_to_remove.each do |channel, subscription|
          event_message = {
            "type"    => JSON::Any.new("channel_event"),
            "event"   => JSON::Any.new("subscription_removed"),
            "channel" => JSON::Any.new(channel),
            "user"    => JSON::Any.new(subscription.identifier),
          }

          # Broadcast sin el lock
          internal_broadcast(channel, event_message)
          
          # Actualizar presencia de forma asíncrona
          spawn { Presence.untrack(subscription.identifier) }

          # Eliminar la suscripción del set
          if subs = @@channels[channel]?
            subs.delete(subscription)
            @@channels.delete(channel) if subs.empty?
          end
        end
      end
    end
  end
end 