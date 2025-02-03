module Hauyna
  module WebSocket
    class Channel
      private def self.internal_subscribe(channel, socket, identifier, metadata)
        @@channels[channel] ||= Set(Subscription).new
        
        # Asegurarnos de que el metadata incluya el estado
        metadata = metadata.merge({
          "state" => JSON::Any.new(metadata["state"]?.try(&.as_s) || "online"),
          "joined_at" => JSON::Any.new(Time.local.to_unix_ms.to_s),
        })
        
        subscription = Subscription.new(socket, identifier, metadata)
        @@channels[channel].add(subscription)

        event_message = {
          "type"     => JSON::Any.new("channel_event"),
          "event"    => JSON::Any.new("subscription_added"),
          "channel"  => JSON::Any.new(channel),
          "user"     => JSON::Any.new(identifier),
          "metadata" => JSON::Any.new(metadata.to_json),
        }

        spawn do
          @@operation_channel.send(
            ChannelOperation.new(:broadcast, {
              channel: channel,
              message: event_message,
            }.as(ChannelOperation::BroadcastData))
          )
        end

        # Asegurarnos de que el estado se incluya en los datos de presencia
        presence_metadata = metadata.merge({
          "channel" => JSON::Any.new(channel),
        })

        Presence.track(identifier, presence_metadata)
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

            spawn do
              @@operation_channel.send(
                ChannelOperation.new(:broadcast, {
                  channel: channel,
                  message: event_message,
                }.as(ChannelOperation::BroadcastData))
              )
            end

            if ConnectionManager.get_identifier(socket) == subscription.identifier
              Presence.untrack(subscription.identifier)
            end
          end
        end
      end

      private def self.internal_broadcast(channel, message)
        message = message.to_json if message.is_a?(Hash)
        if subs = @@channels[channel]?
          subs.each do |subscription|
            spawn do
              begin
                subscription.socket.send(message)
              rescue
                @@operation_channel.send(
                  ChannelOperation.new(:unsubscribe, {
                    channel: channel,
                    socket:  subscription.socket,
                  }.as(ChannelOperation::UnsubscribeData))
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
            "type"  => JSON::Any.new("presence_state"),
            "event" => JSON::Any.new(operation.to_s),
            "state" => JSON::Any.new(presence_state.to_json),
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
