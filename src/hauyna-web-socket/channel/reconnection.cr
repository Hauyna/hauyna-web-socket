module Hauyna
  module WebSocket
    class Channel
      def self.handle_reconnection(socket : HTTP::WebSocket, old_socket : HTTP::WebSocket)
        subscriptions_to_transfer = [] of Tuple(String, Subscription)

        @@mutex.synchronize do
          @@channels.each do |channel, subs|
            if subscription = subs.find { |s| s.socket == old_socket }
              subscriptions_to_transfer << {channel, subscription}
            end
          end
        end

        # Procesar las transferencias a través del canal de operaciones
        subscriptions_to_transfer.each do |channel, old_subscription|
          # Primero desuscribir el socket antiguo
          @@operation_channel.send(
            ChannelOperation.new(:unsubscribe, {
              channel: channel,
              socket:  old_socket,
            }.as(ChannelOperation::UnsubscribeData))
          )

          # Luego suscribir el nuevo socket
          @@operation_channel.send(
            ChannelOperation.new(:subscribe, {
              channel:    channel,
              socket:     socket,
              identifier: old_subscription.identifier,
              metadata:   old_subscription.metadata,
            }.as(ChannelOperation::SubscribeData))
          )

          # Notificar la reconexión
          event_message = {
            "type"     => JSON::Any.new("channel_event"),
            "event"    => JSON::Any.new("subscription_reconnected"),
            "channel"  => JSON::Any.new(channel),
            "user"     => JSON::Any.new(old_subscription.identifier),
            "metadata" => JSON::Any.new(old_subscription.metadata.to_json),
          }

          # Enviar el evento de reconexión a través del canal de operaciones
          @@operation_channel.send(
            ChannelOperation.new(:broadcast, {
              channel: channel,
              message: event_message,
            }.as(ChannelOperation::BroadcastData))
          )
        end

        # Actualizar presencia si es necesario
        if !subscriptions_to_transfer.empty?
          if first_sub = subscriptions_to_transfer.first?
            Presence.update(
              first_sub[1].identifier,
              first_sub[1].metadata.merge({
                "reconnected" => JSON::Any.new(Time.local.to_unix_ms.to_s),
              })
            )
          end
        end
      end

      def self.cleanup_socket(socket : HTTP::WebSocket)
        # Ya no necesitamos este método aquí ya que se maneja a través de CleanupOperation
        @@operation_channel.send(CleanupOperation.new(socket))
      end
    end
  end
end
