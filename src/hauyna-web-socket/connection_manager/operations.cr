module Hauyna
  module WebSocket
    module ConnectionManager
      private class ConnectionOperation
        alias RegisterData = NamedTuple(
          socket: HTTP::WebSocket,
          identifier: String)

        alias UnregisterData = NamedTuple(
          socket: HTTP::WebSocket)

        alias BroadcastData = NamedTuple(
          message: String)

        alias GroupData = NamedTuple(
          identifier: String,
          group_name: String)

        alias StateData = NamedTuple(
          socket: HTTP::WebSocket,
          state: ConnectionState)

        alias OperationData = RegisterData | UnregisterData | BroadcastData | GroupData | StateData

        getter type : Symbol
        getter data : OperationData

        def initialize(@type : Symbol, @data : OperationData)
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
          when :set_state
            data = operation.data.as(ConnectionOperation::StateData)
            internal_set_state(data[:socket], data[:state])
          end
        end
      end
    end
  end
end
