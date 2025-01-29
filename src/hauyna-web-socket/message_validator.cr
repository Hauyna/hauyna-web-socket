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
        when "channel_message"
          validate_channel_message(message)
        when "subscribe_channel"
          validate_channel_subscription(message)
        when "unsubscribe_channel"
          validate_channel_unsubscription(message)
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

      private def self.validate_channel_message(message)
        unless channel = message["channel"]?.try(&.as_s?)
          raise ValidationError.new("El mensaje de canal debe especificar el canal")
        end
        unless message["content"]?
          raise ValidationError.new("El mensaje de canal debe tener contenido")
        end
      end

      private def self.validate_channel_subscription(message)
        unless channel = message["channel"]?.try(&.as_s?)
          raise ValidationError.new("La suscripción debe especificar el canal")
        end
        if metadata = message["metadata"]?
          unless metadata.as_h?
            raise ValidationError.new("Los metadatos deben ser un objeto")
          end
        end
      end

      private def self.validate_channel_unsubscription(message)
        unless channel = message["channel"]?.try(&.as_s?)
          raise ValidationError.new("La desuscripción debe especificar el canal")
        end
      end
    end
  end
end
