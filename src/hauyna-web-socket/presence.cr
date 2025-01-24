module Hauyna
  module WebSocket
    # Clase para manejar la presencia de usuarios en tiempo real
    class Presence
      @@presence = {} of String => Hash(String, JSON::Any)
      @@mutex = Mutex.new

      # Registra la presencia de un usuario con sus metadatos
      def self.track(identifier : String, metadata : Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence[identifier] = metadata
          broadcast_presence_change("join", identifier, metadata)
        end
      end

      # Lista usuarios presentes, opcionalmente filtrados por canal o grupo
      def self.list(channel : String? = nil, group : String? = nil) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          if channel
            @@presence.select { |_, meta| meta["channel"]? == JSON::Any.new(channel) }
          elsif group
            @@presence.select { |_, meta| meta["group"]? == JSON::Any.new(group) }
          else
            @@presence.dup
          end
        end
      end

      # Lista usuarios por múltiples criterios
      def self.list_by(criteria : Hash(String, String)) : Hash(String, Hash(String, JSON::Any))
        @@mutex.synchronize do
          @@presence.select do |_, meta|
            criteria.all? do |key, value|
              meta[key]? == JSON::Any.new(value)
            end
          end
        end
      end

      # Verifica presencia en un contexto específico
      def self.present_in?(identifier : String, context : Hash(String, String)) : Bool
        @@mutex.synchronize do
          if metadata = @@presence[identifier]?
            context.all? do |key, value|
              metadata[key]? == JSON::Any.new(value)
            end
          else
            false
          end
        end
      end

      # Cuenta usuarios por contexto
      def self.count_by(context : Hash(String, String)? = nil) : Int32
        @@mutex.synchronize do
          if context
            list_by(context).size
          else
            @@presence.size
          end
        end
      end

      # Obtiene usuarios en un canal específico
      def self.in_channel(channel : String) : Array(String)
        @@mutex.synchronize do
          @@presence.select { |_, meta| 
            meta["channel"]? == JSON::Any.new(channel) 
          }.keys
        end
      end

      # Obtiene usuarios en un grupo específico
      def self.in_group(group : String) : Array(String)
        @@mutex.synchronize do
          @@presence.select { |_, meta| 
            meta["group"]? == JSON::Any.new(group) 
          }.keys
        end
      end

      # Obtiene el estado de un usuario
      def self.get_state(identifier : String) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@presence[identifier]?
        end
      end

      # Actualiza el estado de un usuario
      def self.update_state(identifier : String, updates : Hash(String, JSON::Any))
        @@mutex.synchronize do
          if current = @@presence[identifier]?
            new_state = current.merge(updates)
            @@presence[identifier] = new_state
            broadcast_presence_change("update", identifier, new_state)
          end
        end
      end

      # Elimina la presencia de un usuario
      def self.untrack(identifier : String)
        @@mutex.synchronize do
          if metadata = @@presence.delete(identifier)
            broadcast_presence_change("leave", identifier, metadata)
          end
        end
      end

      # Actualiza los metadatos de un usuario
      def self.update(identifier : String, metadata : Hash(String, JSON::Any))
        @@mutex.synchronize do
          if @@presence[identifier]?
            @@presence[identifier] = metadata
            broadcast_presence_change("update", identifier, metadata)
          end
        end
      end

      # Obtiene los metadatos de un usuario específico
      def self.get_presence(identifier : String) : Hash(String, JSON::Any)?
        @@mutex.synchronize do
          @@presence[identifier]?
        end
      end

      # Verifica si un usuario está presente
      def self.present?(identifier : String) : Bool
        @@mutex.synchronize do
          @@presence.has_key?(identifier)
        end
      end

      # Cuenta el número total de usuarios presentes
      def self.count : Int32
        @@mutex.synchronize do
          @@presence.size
        end
      end

      private def self.broadcast_presence_change(event : String, identifier : String, metadata : Hash(String, JSON::Any))
        message = {
          type: "presence_change",
          event: event,
          user: identifier,
          metadata: metadata
        }.to_json

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