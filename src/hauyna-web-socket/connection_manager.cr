require "http/web_socket"

module Hauyna
  module WebSocket
    module ConnectionManager
      private class ConnectionOperation
        # Definir los tipos específicos para cada operación
        alias RegisterData = NamedTuple(
          socket: HTTP::WebSocket,
          identifier: String
        )

        alias UnregisterData = NamedTuple(
          socket: HTTP::WebSocket
        )

        alias BroadcastData = NamedTuple(
          message: String
        )

        alias GroupData = NamedTuple(
          identifier: String,
          group_name: String
        )

        # Agregar nuevo tipo para operaciones de estado
        alias StateData = NamedTuple(
          socket: HTTP::WebSocket,
          state: ConnectionState
        )

        # Actualizar OperationData para incluir StateData
        alias OperationData = RegisterData | UnregisterData | BroadcastData | GroupData | StateData

        getter type : Symbol
        getter data : OperationData
        
        def initialize(@type : Symbol, @data : OperationData)
        end
      end

      enum ConnectionState
        Connected     # Socket conectado y funcionando
        Disconnected  # Socket desconectado
        Reconnecting  # En proceso de reconexión
        Error        # Error en la conexión
        Idle         # Conectado pero sin actividad
      end

      @@connections = {} of String => HTTP::WebSocket
      @@socket_to_identifier = {} of HTTP::WebSocket => String
      @@groups = {} of String => Set(String)
      @@operation_channel = ::Channel(ConnectionOperation).new
      @@connection_states = {} of HTTP::WebSocket => ConnectionState
      @@state_timestamps = {} of HTTP::WebSocket => Time

      # Definir transiciones válidas
      private VALID_TRANSITIONS = {
        ConnectionState::Connected => [ConnectionState::Idle, ConnectionState::Disconnected, ConnectionState::Error],
        ConnectionState::Idle => [ConnectionState::Connected, ConnectionState::Disconnected, ConnectionState::Error],
        ConnectionState::Disconnected => [ConnectionState::Reconnecting, ConnectionState::Error],
        ConnectionState::Reconnecting => [ConnectionState::Connected, ConnectionState::Error],
        ConnectionState::Error => [ConnectionState::Reconnecting]
      }

      # Almacenar hooks de estado
      @@state_hooks = {} of Symbol => Array(Proc(HTTP::WebSocket, ConnectionState, ConnectionState, Nil))

      # Registrar hooks para cambios de estado
      def self.on_state_change(&block : HTTP::WebSocket, ConnectionState, ConnectionState -> Nil)
        @@state_hooks[:state_change] ||= [] of Proc(HTTP::WebSocket, ConnectionState, ConnectionState, Nil)
        @@state_hooks[:state_change] << block
      end

      # Validar transición de estado
      private def self.valid_transition?(from : ConnectionState, to : ConnectionState) : Bool
        return true if from == to
        VALID_TRANSITIONS[from]?.try(&.includes?(to)) || false
      end

      # Configuración de reintentos
      class RetryPolicy
        property max_attempts : Int32
        property base_delay : Time::Span
        property max_delay : Time::Span
        property backoff_multiplier : Float64
        property jitter : Float64

        def initialize(
          @max_attempts = 5,
          @base_delay = 1.seconds,
          @max_delay = 30.seconds,
          @backoff_multiplier = 2.0,
          @jitter = 0.1
        )
        end

        def calculate_delay(attempt : Int32) : Time::Span
          return max_delay if attempt >= max_attempts

          # Calcular delay base con backoff exponencial
          delay = base_delay * (backoff_multiplier ** attempt)
          
          # Aplicar jitter aleatorio
          jitter_amount = delay * jitter
          delay += Random.rand(-jitter_amount.total_seconds..jitter_amount.total_seconds).seconds
          
          # No exceder el máximo
          [delay, max_delay].min
        end
      end

      # Almacenar políticas por socket
      @@retry_policies = {} of HTTP::WebSocket => RetryPolicy
      @@retry_attempts = {} of HTTP::WebSocket => Int32

      # Configurar política de reintentos
      def self.set_retry_policy(socket : HTTP::WebSocket, policy : RetryPolicy)
        @@retry_policies[socket] = policy
        @@retry_attempts[socket] = 0
      end

      # Manejar reintentos
      private def self.handle_retry(socket : HTTP::WebSocket)
        return unless policy = @@retry_policies[socket]?
        attempts = @@retry_attempts[socket] ||= 0

        if attempts < policy.max_attempts
          delay = policy.calculate_delay(attempts)
          @@retry_attempts[socket] += 1

          # Programar reintento
          spawn do
            sleep delay
            if valid_transition?(ConnectionState::Error, ConnectionState::Reconnecting)
              set_connection_state(socket, ConnectionState::Reconnecting)
            end
          end
        end
      end

      # Modificar set_connection_state para usar validación y hooks
      def self.set_connection_state(socket : HTTP::WebSocket, new_state : ConnectionState) : Bool
        current_state = @@connection_states[socket]?
        
        # Si no hay estado actual, cualquier estado es válido
        unless current_state
          internal_set_state(socket, new_state)
          return true
        end

        # Validar transición
        unless valid_transition?(current_state, new_state)
          return false
        end

        # Ejecutar hooks antes del cambio
        if hooks = @@state_hooks[:state_change]?
          hooks.each do |hook|
            begin
              hook.call(socket, current_state, new_state)
            rescue ex
              # Log error pero continuar con otros hooks
              puts "Error en hook de estado: #{ex.message}"
            end
          end
        end

        # Realizar el cambio de estado
        internal_set_state(socket, new_state)

        # Manejar reintentos si es necesario
        if new_state == ConnectionState::Error
          handle_retry(socket)
        elsif new_state == ConnectionState::Connected
          # Resetear contador de reintentos al conectar exitosamente
          @@retry_attempts[socket] = 0
        end

        true
      end

      # Agregar método para transiciones personalizadas
      def self.add_valid_transition(from : ConnectionState, to : ConnectionState)
        VALID_TRANSITIONS[from] ||= [] of ConnectionState
        VALID_TRANSITIONS[from] << to unless VALID_TRANSITIONS[from].includes?(to)
      end

      # Limpiar al desconectar
      private def self.internal_unregister(socket)
        if identifier = @@socket_to_identifier[socket]?
          @@connections.delete(identifier)
          @@socket_to_identifier.delete(socket)
          @@connection_states.delete(socket)
          @@state_timestamps.delete(socket)
          @@retry_policies.delete(socket)
          @@retry_attempts.delete(socket)
          @@groups.each do |_, members|
            members.delete(identifier)
          end
        end
      end

      # Iniciar el procesador de operaciones
      spawn do
        loop do
          operation = @@operation_channel.receive
          case operation.type
          when :register
            data = operation.data.as(ConnectionOperation::RegisterData)
            internal_register(data[:socket], data[:identifier])
          when :unregister
            data = operation.data.as(ConnectionOperation::UnregisterData)
            internal_unregister(data[:socket])
          when :broadcast
            data = operation.data.as(ConnectionOperation::BroadcastData)
            internal_broadcast(data[:message])
          when :add_to_group
            data = operation.data.as(ConnectionOperation::GroupData)
            internal_add_to_group(data[:identifier], data[:group_name])
          when :set_state # Nuevo caso para manejo de estados
            data = operation.data.as(ConnectionOperation::StateData)
            internal_set_state(data[:socket], data[:state])
          end
        end
      end

      private def self.internal_register(socket, identifier)
        @@connections[identifier] = socket
        @@socket_to_identifier[socket] = identifier
        
        # Agregar estado inicial
        @@connection_states[socket] = ConnectionState::Connected
        @@state_timestamps[socket] = Time.local
      end

      private def self.internal_broadcast(message)
        @@connections.each_value do |socket|
          spawn do
            begin
              socket.send(message)
            rescue
              @@operation_channel.send(
                ConnectionOperation.new(:unregister, {
                  socket: socket
                }.as(ConnectionOperation::UnregisterData))
              )
            end
          end
        end
      end

      private def self.internal_add_to_group(identifier, group_name)
        @@groups[group_name] ||= Set(String).new
        @@groups[group_name].add(identifier)
      end

      # Agregar método interno para manejar estados
      private def self.internal_set_state(socket, state)
        @@connection_states[socket] = state
        @@state_timestamps[socket] = Time.local
        
        if identifier = get_identifier(socket)
          state_message = {
            "type" => JSON::Any.new("connection_state"),
            "user" => JSON::Any.new(identifier),
            "state" => JSON::Any.new(state.to_s),
            "timestamp" => JSON::Any.new(Time.local.to_unix_ms.to_s)
          }
          
          begin
            socket.send(state_message.to_json)
          rescue
            @@connection_states[socket] = ConnectionState::Error
          end
        end
      end

      # API pública
      def self.register(socket : HTTP::WebSocket, identifier : String)
        @@operation_channel.send(
          ConnectionOperation.new(:register, {
            socket: socket,
            identifier: identifier
          }.as(ConnectionOperation::RegisterData))
        )
      end

      def self.unregister(socket : HTTP::WebSocket)
        @@operation_channel.send(
          ConnectionOperation.new(:unregister, {
            socket: socket
          }.as(ConnectionOperation::UnregisterData))
        )
      end

      def self.broadcast(message : String)
        @@operation_channel.send(
          ConnectionOperation.new(:broadcast, {
            message: message
          }.as(ConnectionOperation::BroadcastData))
        )
      end

      def self.add_to_group(identifier : String, group_name : String)
        @@operation_channel.send(
          ConnectionOperation.new(:add_to_group, {
            identifier: identifier,
            group_name: group_name
          }.as(ConnectionOperation::GroupData))
        )
      end

      # Obtiene el socket asociado a un identificador
      def self.get_socket(identifier : String) : HTTP::WebSocket?
        @@connections[identifier]
      end

      # Añade un usuario a un grupo específico
      def self.remove_from_group(identifier : String, group_name : String)
        if group = @@groups[group_name]?
          group.delete(identifier)
          @@groups.delete(group_name) if group.empty?
        end
      end

      def self.send_to_one(identifier : String, message : String)
        if socket = @@connections[identifier]?
          begin
            socket.send(message)
          rescue
          end
        end
      end

      def self.send_to_many(identifiers : Array(String), message : String)
        identifiers.each do |identifier|
          send_to_one(identifier, message)
        end
      end

      def self.send_to_group(group_name : String, message : String)
        # Obtener miembros del grupo bajo el lock
        members = @@groups[group_name]?.try(&.dup) || Set(String).new

        # Enviar mensajes fuera del lock
        members.each do |identifier|
          send_to_one(identifier, message)
        end
      end

      def self.get_group_members(group_name : String) : Set(String)
        members = @@groups[group_name]?.try(&.dup) || Set(String).new
        puts "Miembros del grupo #{group_name}: #{members.inspect}"
        members
      end

      def self.clear
        @@connections.clear
        @@groups.clear
        @@socket_to_identifier.clear
      end

      def self.get_identifier(socket : HTTP::WebSocket) : String?
        @@socket_to_identifier[socket]
      end

      def self.all_connections : Array(HTTP::WebSocket)
        @@connections.values
      end

      def self.count : Int32
        @@connections.size
      end

      # Obtener todos los grupos a los que pertenece un usuario
      def self.get_user_groups(identifier : String) : Array(String)
        groups = [] of String
        @@groups.each do |group_name, members|
          if members.includes?(identifier)
            groups << group_name
          end
        end
        groups
      end

      def self.is_in_group?(identifier : String, group_name : String) : Bool
        if group = @@groups[group_name]?
          group.includes?(identifier)
        else
          false
        end
      end

      def self.get_connection_state(socket : HTTP::WebSocket) : ConnectionState?
        @@connection_states[socket]?
      end

      def self.get_state_timestamp(socket : HTTP::WebSocket) : Time?
        @@state_timestamps[socket]?
      end

      def self.connections_in_state(state : ConnectionState) : Array(HTTP::WebSocket)
        @@connection_states.select { |_, s| s == state }.keys
      end
    end
  end
end
