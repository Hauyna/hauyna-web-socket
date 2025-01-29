module Hauyna
  module WebSocket
    class ErrorHandler
      def self.handle(socket : HTTP::WebSocket, error : Exception)
        case error
        when MessageValidator::ValidationError
          send_error(socket, "validation_error", error.message || "Error de validación")
        when JSON::ParseException
          send_error(socket, "parse_error", "Formato de mensaje inválido")
        when IO::Error
          send_error(socket, "connection_error", "Error de conexión")
        when Socket::Error
          send_error(socket, "socket_error", "Error en el socket")
        else
          Log.error { "Error no manejado: #{error.message}\n#{error.backtrace?.try &.join("\n")}" }
          send_error(socket, "internal_error", "Error interno del servidor")
        end
      end

      private def self.send_error(socket : HTTP::WebSocket, type : String, message : String)
        error_message = {
          type:       "error",
          error_type: type,
          message:    message,
        }.to_json

        begin
          socket.send(error_message)
        rescue
          # Si falla el envío del error, cerramos la conexión
          socket.close
        end
      end
    end
  end
end
