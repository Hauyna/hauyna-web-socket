module Hauyna
  module WebSocket
    class Channel
      class Subscription
        property socket : HTTP::WebSocket
        property identifier : String
        property metadata : Hash(String, JSON::Any)

        def initialize(@socket, @identifier, @metadata = {} of String => JSON::Any)
        end
      end

      @@channels = {} of String => Set(Subscription)

      def self.subscription_count(channel : String) : Int32
        @@channels[channel]?.try(&.size) || 0
      end

      def self.presence_data(channel : String) : Hash(String, JSON::Any)
        presence_data = {} of String => JSON::Any

        if channel_subs = @@channels[channel]?
          channel_subs.each do |subscription|
            next if subscription.socket.closed?

            metadata = subscription.metadata
            presence_data[subscription.identifier] = JSON::Any.new({
              "user_id"      => JSON::Any.new(subscription.identifier),
              "metadata"     => JSON::Any.new(metadata.to_json),
              "state"        => JSON::Any.new(ConnectionManager.get_connection_state(subscription.socket).to_s),
              "connected_at" => metadata["joined_at"]?.try(&.as_s) || JSON::Any.new(Time.local.to_unix_ms.to_s),
            }.to_json)
          end
        end

        presence_data
      end
    end
  end
end
