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
        when RuntimeError
          Log.error { "Error de ejecución: #{error.message}\n#{error.backtrace?.try &.join("\n")}" }
          send_error(socket, "runtime_error", "Error durante la ejecución")
        when ArgumentError
          send_error(socket, "argument_error", "Argumentos inválidos en la operación")
        when IndexError
          send_error(socket, "index_error", "Error de acceso a índice")
        when KeyError
          send_error(socket, "key_error", "Error de acceso a clave")
        when TypeCastError
          send_error(socket, "type_error", "Error de conversión de tipo")
        when DivisionByZeroError
          send_error(socket, "arithmetic_error", "Error aritmético")
        when OverflowError
          send_error(socket, "overflow_error", "Error de desbordamiento")
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
          timestamp:  Time.local.to_unix_ms,
        }.to_json

        begin
          socket.send(error_message)
        rescue ex
          Log.error { "Error al enviar mensaje de error: #{ex.message}" }
          # Si falla el envío del error, cerramos la conexión
          begin
            socket.close(4000, "Error interno del servidor")
          rescue
            # Ignoramos errores al cerrar el socket
          end
        end
      end

      # Método auxiliar para registrar errores en el log
      private def self.log_error(error : Exception, context : String? = nil)
        message = String.build do |str|
          str << "#{context}: " if context
          str << error.message
          if backtrace = error.backtrace?
            str << "\n"
            str << backtrace.join("\n")
          end
        end
        Log.error { message }
      end
    end
  end
end
