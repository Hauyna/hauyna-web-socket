module Hauyna
  module WebSocket
    class Channel
      @@channels = {} of String => Set(Subscription)
      @@operation_channel = ::Channel(ChannelOperation).new
      @@mutex = Mutex.new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          process_operation(operation)
        end
      end

      private def self.process_operation(operation : ChannelOperation)
        @@mutex.synchronize do
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
      rescue ex
        puts "ERROR procesando operación: #{ex.message}"
        puts ex.backtrace.join("\n")
      end

      # API pública
      def self.subscribe(channel : String, socket : HTTP::WebSocket, identifier : String, metadata = {} of String => JSON::Any)
        # Verificar que el socket esté registrado
        return unless ConnectionManager.get_identifier(socket)

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

      # Métodos de consulta
      def self.subscription_count(channel : String) : Int32
        @@channels[channel]?.try(&.size) || 0
      end

      def self.subscribers(channel : String) : Array(String)
        @@channels[channel]?.try(&.map(&.identifier).to_a) || [] of String
      end

      def self.subscribed?(channel : String, socket : HTTP::WebSocket) : Bool
        @@channels[channel]?.try(&.any? { |s| s.socket == socket }) || false
      end

      def self.get_subscription_metadata(channel : String, socket : HTTP::WebSocket) : Hash(String, JSON::Any)?
        @@channels[channel]?.try(&.find { |s| s.socket == socket }).try(&.metadata)
      end

      def self.presence_data(channel : String) : Hash(String, JSON::Any)
        puts "DEBUG: Obteniendo datos de presencia para canal: #{channel}"
        
        # Obtener datos de presencia filtrados por canal
        presence_data = Presence.list_by_channel(channel)
        puts "DEBUG: Datos de presencia raw: #{presence_data.inspect}"
        
        # Formatear los datos para la respuesta
        formatted_data = {} of String => JSON::Any
        presence_data.each do |identifier, data|
          metadata = data["metadata"]?.try(&.as_h) || {} of String => JSON::Any
          state = data["state"]?.try(&.as_s) || "unknown"
          
          formatted_data[identifier] = JSON::Any.new({
            "user_id" => JSON::Any.new(identifier),
            "metadata" => JSON::Any.new(metadata.to_json),
            "state" => JSON::Any.new(state),
            "connected_at" => metadata["joined_at"]?.try(&.as_s) || Time.local.to_unix_ms.to_s
          }.to_json)
        end

        puts "DEBUG: Datos de presencia formateados: #{formatted_data.inspect}"
        formatted_data
      end

      def self.update_presence(socket : HTTP::WebSocket, state : ConnectionManager::ConnectionState)
        if identifier = ConnectionManager.get_identifier(socket)
          subscribed_channels(socket).each do |channel|
            presence_metadata = {
              "state" => JSON::Any.new(state.to_s),
              "channel" => JSON::Any.new(channel),
              "updated_at" => JSON::Any.new(Time.local.to_unix_ms.to_s)
            }
            
            Presence.update(identifier, presence_metadata)
            puts "DEBUG: Presencia actualizada para #{identifier} en canal #{channel} - Estado: #{state}"
          end
        end
      end

      def self.subscribed_channels(socket : HTTP::WebSocket) : Array(String)
        channels = [] of String
        
        @@channels.each do |channel, subs|
          if subs.any? { |s| s.socket == socket }
            channels << channel
          end
        end
        
        channels
      end

      def self.cleanup_socket(socket : HTTP::WebSocket)
        @@channels.each do |channel, subs|
          if subs.any? { |s| s.socket == socket }
            unsubscribe(channel, socket)
          end
        end
      end
    end
  end
end 