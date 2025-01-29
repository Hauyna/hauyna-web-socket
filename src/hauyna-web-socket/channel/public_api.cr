module Hauyna
  module WebSocket
    class Channel
      # API pública
      def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
        data = {
          channel:    channel,
          socket:     socket,
          identifier: identifier,
          metadata:   metadata,
        }
        @@operation_channel.send(
          ChannelOperation.new(:subscribe, data.as(ChannelOperation::SubscribeData))
        )
      end

      def self.unsubscribe(channel : String, socket : HTTP::WebSocket)
        data = {
          channel: channel,
          socket:  socket,
        }
        @@operation_channel.send(
          ChannelOperation.new(:unsubscribe, data.as(ChannelOperation::UnsubscribeData))
        )
      end

      def self.broadcast_to(channel : String, message : Hash(String, JSON::Any) | String)
        data = {
          channel: channel,
          message: message,
        }
        @@operation_channel.send(
          ChannelOperation.new(:broadcast, data.as(ChannelOperation::BroadcastData))
        )
      end

      def self.subscription_count(channel : String) : Int32
        @@mutex.synchronize do
          @@channels[channel]?.try(&.size) || 0
        end
      end

      def self.subscribers(channel : String) : Array(String)
        @@mutex.synchronize do
          @@channels[channel]?.try(&.map(&.identifier).to_a) || [] of String
        end
      end

      def self.subscribed_channels(socket : HTTP::WebSocket) : Array(String)
        subscribed_channels_unsafe(socket)
      end

      def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
        @@mutex.synchronize do
          @@channels[channel]?.try(&.any? { |s| s.socket == socket }) || false
        end
      end

      def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@channels[channel]?.try(&.find { |s| s.socket == socket }).try(&.metadata)
        end
      end
    end
  end
end
