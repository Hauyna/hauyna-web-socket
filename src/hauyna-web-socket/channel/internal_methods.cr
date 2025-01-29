module Hauyna
  module WebSocket
    class Channel
      private def self.internal_subscribe(channel, socket, identifier, metadata)
        @@channels[channel] ||= Set(Subscription).new
        subscription = Subscription.new(socket, identifier, metadata)
        @@channels[channel].add(subscription)

        event_message = {
          "type"     => JSON::Any.new("channel_event"),
          "event"    => JSON::Any.new("subscription_added"),
          "channel"  => JSON::Any.new(channel),
          "user"     => JSON::Any.new(identifier),
          "metadata" => JSON::Any.new(metadata.to_json),
        }

        internal_broadcast(channel, event_message)
        
        Presence.track(identifier, metadata.merge({
          "channel" => JSON::Any.new(channel),
        }))
        
        notify_presence(:join)
      end

      private def self.internal_unsubscribe(channel, socket)
        if channel_subs = @@channels[channel]?
          if subscription = channel_subs.find { |s| s.socket == socket }
            channel_subs.delete(subscription)
            @@channels.delete(channel) if channel_subs.empty?

            event_message = {
              "type"    => JSON::Any.new("channel_event"),
              "event"   => JSON::Any.new("subscription_removed"),
              "channel" => JSON::Any.new(channel),
              "user"    => JSON::Any.new(subscription.identifier),
            }

            internal_broadcast(channel, event_message)
            
            # Actualizar presencia
            if ConnectionManager.get_identifier(socket) == subscription.identifier
              Presence.update(subscription.identifier, {
                "status" => JSON::Any.new("offline"),
                "left_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
              })
            end
          end
        end
      end

      private def self.internal_broadcast(channel, message)
        message = message.to_json if message.is_a?(Hash(String, JSON::Any))
        if subs = @@channels[channel]?
          subs.each do |subscription|
            spawn do
              begin
                subscription.socket.send(message)
              rescue
                data = {
                  channel: channel,
                  socket: subscription.socket
                }
                @@operation_channel.send(
                  ChannelOperation.new(:unsubscribe, data.as(ChannelOperation::UnsubscribeData))
                )
              end
            end
          end
        end
      end

      private def self.notify_presence(operation)
        case operation
        when :join, :leave, :update
          presence_state = Presence.list
          presence_message = {
            "type" => JSON::Any.new("presence_state"),
            "event" => JSON::Any.new(operation.to_s),
            "state" => JSON::Any.new(presence_state.to_json)
          }

          @@channels.each do |channel, _|
            internal_broadcast(channel, presence_message)
          end
        end
      end

      private def self.subscribed_channels_unsafe(socket : HTTP::WebSocket) : Array(String)
        channels = [] of String
        @@channels.each do |channel, subs|
          if subs.any? { |s| s.socket == socket }
            channels << channel
          end
        end
        channels
      end
    end
  end
end 