module Hauyna
  module WebSocket
    # Clase para manejar la presencia de usuarios en tiempo real
    class Presence
      private class PresenceOperation
        # Definir los tipos específicos para cada operación
        alias TrackData = NamedTuple(
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias UntrackData = NamedTuple(
          identifier: String
        )

        alias UpdateData = NamedTuple(
          identifier: String,
          metadata: Hash(String, JSON::Any)
        )

        alias OperationData = TrackData | UntrackData | UpdateData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end

      @@presence = {} of String => Hash(String, JSON::Any)
      @@operation_channel = ::Channel(PresenceOperation).new

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          case operation.type
          when :track
            data = operation.data.as(PresenceOperation::TrackData)
            internal_track(data[:identifier], data[:metadata])
          when :untrack
            data = operation.data.as(PresenceOperation::UntrackData)
            internal_untrack(data[:identifier])
          when :update
            data = operation.data.as(PresenceOperation::UpdateData)
            internal_update(data[:identifier], data[:metadata])
          end
        end
      end

      private def self.internal_track(identifier, metadata)
        @@presence[identifier] = metadata
        spawn do
          broadcast_presence_change("join", identifier, metadata)
        end
      end

      private def self.internal_untrack(identifier)
        if metadata = @@presence.delete(identifier)
          spawn do
            broadcast_presence_change("leave", identifier, metadata)
          end
        end
      end

      private def self.internal_update(identifier, metadata)
        if @@presence[identifier]?
          @@presence[identifier] = metadata
          spawn do
            broadcast_presence_change("update", identifier, metadata)
          end
        end
      end

      # API pública
      def self.track(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:track, {
            identifier: identifier,
            metadata: metadata
          }.as(PresenceOperation::TrackData))
        )
      end

      def self.untrack(identifier : String)
        @@operation_channel.send(
          PresenceOperation.new(:untrack, {
            identifier: identifier
          }.as(PresenceOperation::UntrackData))
        )
      end

      def self.update(identifier : String, metadata : Hash(String, JSON::Any))
        @@operation_channel.send(
          PresenceOperation.new(:update, {
            identifier: identifier,
            metadata: metadata
          }.as(PresenceOperation::UpdateData))
        )
      end

      # Lista usuarios presentes, opcionalmente filtrados por canal o grupo
      def self.list(channel : String? = nil, group : String? = nil) : Hash(String, Hash(String, JSON::Any))
        @@presence.select { |_, meta| meta["channel"]? == JSON::Any.new(channel) }
      end

      # Lista usuarios por múltiples criterios
      def self.list_by(criteria : Hash(String, String)) : Hash(String, Hash(String, JSON::Any))
        @@presence.select do |_, meta|
          criteria.all? do |key, value|
            meta[key]? == JSON::Any.new(value)
          end
        end
      end

      # Verifica presencia en un contexto específico
      def self.present_in?(identifier : String, context : Hash(String, String)) : Bool
        if metadata = @@presence[identifier]?
          context.all? do |key, value|
            metadata[key]? == JSON::Any.new(value)
          end
        else
          false
        end
      end

      # Cuenta usuarios por contexto
      def self.count_by(context : Hash(String, String)? = nil) : Int32
        if context
          list_by(context).size
        else
          @@presence.size
        end
      end

      # Obtiene usuarios en un canal específico
      def self.in_channel(channel : String) : Array(String)
        @@presence.select { |_, meta|
          meta["channel"]? == JSON::Any.new(channel)
        }.keys
      end

      # Obtiene usuarios en un grupo específico
      def self.in_group(group : String) : Array(String)
        @@presence.select { |_, meta|
          meta["group"]? == JSON::Any.new(group)
        }.keys
      end

      # Obtiene el estado de un usuario
      def self.get_state(identifier : String) : Hash(String, JSON::Any)?
        @@presence[identifier]?
      end

      # Obtiene los metadatos de un usuario específico
      def self.get_presence(identifier : String) : Hash(String, JSON::Any)?
        @@presence[identifier]?
      end

      # Verifica si un usuario está presente
      def self.present?(identifier : String) : Bool
        @@presence.has_key?(identifier)
      end

      # Cuenta el número total de usuarios presentes
      def self.count : Int32
        @@presence.size
      end

      private def self.broadcast_presence_change(event : String, identifier : String, metadata : Hash(String, JSON::Any))
        message = {
          type:     "presence_change",
          event:    event,
          user:     identifier,
          metadata: metadata,
        }.to_json

        # Realizar broadcasts de forma asíncrona para evitar deadlocks
        spawn do
          # Broadcast general
          ConnectionManager.broadcast(message)

          # Broadcast específico al canal si existe
          if channel = metadata["channel"]?.try(&.as_s)
            Channel.broadcast_to(channel, message)
          end
        end
      end
    end
  end
end
