module Hauyna
  module WebSocket
    class MessageValidator
      class ValidationError < Exception; end

      def self.validate_message(message : JSON::Any)
        raise ValidationError.new("Mensaje vacío") if message.as_h?.try(&.empty?)

        # Validar tipo de mensaje
        unless type = message["type"]?.try(&.as_s?)
          raise ValidationError.new("El mensaje debe tener un tipo")
        end

        # Validar contenido según tipo
        case type
        when "broadcast"
          validate_broadcast(message)
        when "private"
          validate_private(message)
        when "group"
          validate_group(message)
        end
      end

      private def self.validate_broadcast(message)
        unless message["message"]?
          raise ValidationError.new("El mensaje broadcast debe tener contenido")
        end
      end

      private def self.validate_private(message)
        unless message["to"]?.try(&.as_s?)
          raise ValidationError.new("El mensaje privado debe especificar destinatario")
        end
        unless message["message"]?
          raise ValidationError.new("El mensaje privado debe tener contenido")
        end
      end

      private def self.validate_group(message)
        unless message["room"]?.try(&.as_s?)
          raise ValidationError.new("El mensaje de grupo debe especificar sala")
        end
        unless message["message"]?
          raise ValidationError.new("El mensaje de grupo debe tener contenido")
        end
      end
    end
  end
end
