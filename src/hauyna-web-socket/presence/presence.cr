require "./presence_operation" # Primero las definiciones de tipos
require "./base"               # Luego la inicialización y API pública
require "./state_management"   # Luego el manejo de estado
require "./queries"            # Luego las consultas
require "./notifications"      # Finalmente las notificaciones

module Hauyna
  module WebSocket
    module Presence
    end
  end
end
