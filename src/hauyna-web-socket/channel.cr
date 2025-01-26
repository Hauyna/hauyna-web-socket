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

          event_message = {
            "type"     => JSON::Any.new("channel_event"),
            "event"    => JSON::Any.new("subscription_added"),
            "channel"  => JSON::Any.new(channel),
            "user"     => JSON::Any.new(identifier),
            "metadata" => JSON::Any.new(metadata.to_json),
          }

          broadcast_to(channel, event_message)

          # Actualizar presencia si está habilitada
          Presence.track(identifier, metadata.merge({
            "channel" => JSON::Any.new(channel),
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

              event_message = {
                "type"    => JSON::Any.new("channel_event"),
                "event"   => JSON::Any.new("subscription_removed"),
                "channel" => JSON::Any.new(channel),
                "user"    => JSON::Any.new(subscription.identifier),
              }

              broadcast_to(channel, event_message)

              # Actualizar presencia
              Presence.untrack(subscription.identifier)
            end
          end
        end
      end

      # Envía mensaje a todos los suscriptores de un canal
      def self.broadcast_to(channel : String, message : Hash(String, JSON::Any) | String)
        message = message.to_json if message.is_a?(Hash(String, JSON::Any))

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

      # Obtiene canales suscritos por un socket sin bloquear el mutex nuevamente
      private def self.subscribed_channels_unsafe(socket : HTTP::WebSocket) : Array(String)
        channels = [] of String
        @@channels.each do |channel, subs|
          if subs.any? { |s| s.socket == socket }
            channels << channel
          end
        end
        channels
      end

      # Obtiene canales suscritos por un socket
      def self.subscribed_channels(socket : HTTP::WebSocket) : Array(String)
        @@mutex.synchronize do
          subscribed_channels_unsafe(socket)
        end
      end

      # Limpia todas las suscripciones de un socket
      def self.cleanup_socket(socket : HTTP::WebSocket)
        @@mutex.synchronize do
          # Obtener los canales mientras tenemos el lock
          channels_to_cleanup = subscribed_channels_unsafe(socket)

          # Limpiar cada canal
          channels_to_cleanup.each do |channel|
            if channel_subs = @@channels[channel]?
              if subscription = channel_subs.find { |s| s.socket == socket }
                channel_subs.delete(subscription)
                @@channels.delete(channel) if channel_subs.empty?

                # Notificar la desuscripción sin volver a bloquear el mutex
                event_message = {
                  "type"    => JSON::Any.new("channel_event"),
                  "event"   => JSON::Any.new("subscription_removed"),
                  "channel" => JSON::Any.new(channel),
                  "user"    => JSON::Any.new(subscription.identifier),
                }

                # Enviar el mensaje directamente a los sockets restantes
                channel_subs.each do |sub|
                  begin
                    sub.socket.send(event_message.to_json)
                  rescue
                    # Ignorar errores de envío durante la limpieza
                  end
                end

                # Actualizar presencia
                Presence.untrack(subscription.identifier)
              end
            end
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
