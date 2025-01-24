module Hauyna
  module WebSocket
    # Sistema de canales para organizar comunicaciones por tópicos
    class Channel
      class Subscription
        property socket : HTTP::WebSocket
        property identifier : String
        property metadata : Hash(String, JSON::Any)

        def initialize(@socket, @identifier, @metadata = {} of String => JSON::Any)
        end
      end

      @@channels = {} of String => Set(Subscription)
      @@mutex = Mutex.new

      # Suscribe un socket a un canal
      def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
        @@mutex.synchronize do
          @@channels[channel] ||= Set(Subscription).new
          subscription = Subscription.new(socket, identifier, metadata)
          @@channels[channel].add(subscription)
          
          broadcast_to(channel, {
            type: "channel_event",
            event: "subscription_added",
            channel: channel,
            user: identifier,
            metadata: metadata
          })

          # Actualizar presencia si está habilitada
          Presence.track(identifier, metadata.merge({
            "channel" => JSON::Any.new(channel)
          }))
        end
      end

      # Desuscribe un socket de un canal
      def self.unsubscribe(channel : String, socket : HTTP::WebSocket)
        @@mutex.synchronize do
          if channel_subs = @@channels[channel]?
            if subscription = channel_subs.find { |s| s.socket == socket }
              channel_subs.delete(subscription)
              @@channels.delete(channel) if channel_subs.empty?

              broadcast_to(channel, {
                type: "channel_event",
                event: "subscription_removed",
                channel: channel,
                user: subscription.identifier
              })

              # Actualizar presencia
              Presence.untrack(subscription.identifier)
            end
          end
        end
      end

      # Envía mensaje a todos los suscriptores de un canal
      def self.broadcast_to(channel : String, message : Hash | String)
        message = message.to_json if message.is_a?(Hash)
        
        @@mutex.synchronize do
          if subs = @@channels[channel]?
            subs.each do |subscription|
              begin
                subscription.socket.send(message)
              rescue ex
                # Si hay error al enviar, limpiar la suscripción
                unsubscribe(channel, subscription.socket)
              end
            end
          end
        end
      end

      # Lista suscriptores de un canal
      def self.subscribers(channel : String) : Array(String)
        @@mutex.synchronize do
          if subs = @@channels[channel]?
            subs.map(&.identifier).to_a
          else
            [] of String
          end
        end
      end

      # Obtiene canales suscritos por un socket
      def self.subscribed_channels(socket : HTTP::WebSocket) : Array(String)
        @@mutex.synchronize do
          channels = [] of String
          @@channels.each do |channel, subs|
            if subs.any? { |s| s.socket == socket }
              channels << channel
            end
          end
          channels
        end
      end

      # Limpia todas las suscripciones de un socket
      def self.cleanup_socket(socket : HTTP::WebSocket)
        @@mutex.synchronize do
          channels_to_cleanup = subscribed_channels(socket)
          channels_to_cleanup.each do |channel|
            unsubscribe(channel, socket)
          end
        end
      end

      # Verifica si un socket está suscrito a un canal
      def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
        @@mutex.synchronize do
          if subs = @@channels[channel]?
            subs.any? { |s| s.socket == socket }
          else
            false
          end
        end
      end

      # Obtiene la metadata de una suscripción
      def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          if subs = @@channels[channel]?
            if subscription = subs.find { |s| s.socket == socket }
              subscription.metadata
            end
          end
        end
      end
    end
  end
end 