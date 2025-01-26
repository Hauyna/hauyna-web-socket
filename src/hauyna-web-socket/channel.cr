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

      # Usar Channel para operaciones concurrentes
      private class ChannelOperation
        # Definir los tipos específicos para cada operación
        alias SubscribeData = NamedTuple(
          channel: String,
          socket: HTTP::WebSocket,
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias UnsubscribeData = NamedTuple(
          channel: String,
          socket: HTTP::WebSocket
        )

        alias BroadcastData = NamedTuple(
          channel: String,
          message: String | Hash(String, JSON::Any)
        )

        alias OperationData = SubscribeData | UnsubscribeData | BroadcastData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end

      @@channels = {} of String => Set(Subscription)
      @@operation_channel = ::Channel(ChannelOperation).new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          case operation.type
          when :subscribe
            data = operation.data.as(ChannelOperation::SubscribeData)
            internal_subscribe(data[:channel], data[:socket], data[:identifier], data[:metadata])
          when :unsubscribe
            data = operation.data.as(ChannelOperation::UnsubscribeData)
            internal_unsubscribe(data[:channel], data[:socket])
          when :broadcast
            data = operation.data.as(ChannelOperation::BroadcastData)
            internal_broadcast(data[:channel], data[:message])
          end
        end
      end

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
        
        # Actualizar presencia
        Presence.track(identifier, metadata.merge({
          "channel" => JSON::Any.new(channel),
        }))
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
            Presence.untrack(subscription.identifier)
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

      # API pública
      def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
        data = {
          channel: channel,
          socket: socket,
          identifier: identifier,
          metadata: metadata
        }
        @@operation_channel.send(
          ChannelOperation.new(:subscribe, data.as(ChannelOperation::SubscribeData))
        )
      end

      def self.unsubscribe(channel : String, socket : HTTP::WebSocket)
        data = {
          channel: channel,
          socket: socket
        }
        @@operation_channel.send(
          ChannelOperation.new(:unsubscribe, data.as(ChannelOperation::UnsubscribeData))
        )
      end

      def self.broadcast_to(channel : String, message : Hash(String, JSON::Any) | String)
        data = {
          channel: channel,
          message: message
        }
        @@operation_channel.send(
          ChannelOperation.new(:broadcast, data.as(ChannelOperation::BroadcastData))
        )
      end

      # Lista suscriptores de un canal
      def self.subscribers(channel : String) : Array(String)
        @@channels[channel]?.try(&.map(&.identifier).to_a) || [] of String
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
        subscribed_channels_unsafe(socket)
      end

      # Limpia todas las suscripciones de un socket
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

      # Verifica si un socket está suscrito a un canal
      def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
        @@channels[channel]?.try(&.any? { |s| s.socket == socket }) || false
      end

      # Obtiene la metadata de una suscripción
      def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
        if subs = @@channels[channel]?
          if subscription = subs.find { |s| s.socket == socket }
            subscription.metadata
          end
        end
      end

      # Maneja la reconexión de un socket, transfiriendo todas sus suscripciones
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
    end
  end
end
