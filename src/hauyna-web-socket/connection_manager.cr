require "http/web_socket"

module Hauyna
    module WebSocket
      module ConnectionManager
        @@connections = {} of String => HTTP::WebSocket
        @@socket_to_identifier = {} of HTTP::WebSocket => String
        @@groups = {} of String => Set(String)
        @@mutex = Mutex.new
  
        # Registra una nueva conexión WebSocket con su identificador
        def self.register(socket : HTTP::WebSocket, identifier : String)
          @@mutex.synchronize do
            @@connections[identifier] = socket
            @@socket_to_identifier[socket] = identifier
          end
        end
  
        # Elimina una conexión WebSocket
        def self.unregister(socket : HTTP::WebSocket)
          @@mutex.synchronize do
            if identifier = @@socket_to_identifier[socket]?
              @@connections.delete(identifier)
              @@socket_to_identifier.delete(socket)
              
              # Eliminar el identificador de todos los grupos
              @@groups.each do |_, members|
                members.delete(identifier)
              end
            end
          end
        end
  
        # Obtiene el socket asociado a un identificador
        def self.get_socket(identifier : String) : HTTP::WebSocket?
          @@mutex.synchronize do
            @@connections[identifier]
          end
        end
  
        # Añade un cliente a un grupo
        def self.add_to_group(identifier : String, group_name : String)
          @@mutex.synchronize do
            @@groups[group_name] ||= Set(String).new
            @@groups[group_name].add(identifier)
          end
        end
  
        # Elimina un cliente de un grupo
        def self.remove_from_group(identifier : String, group_name : String)
          @@mutex.synchronize do
            if group = @@groups[group_name]?
              group.delete(identifier)
              @@groups.delete(group_name) if group.empty?
            end
          end
        end
  
        # Envía un mensaje a todos los clientes conectados
        def self.broadcast(message : String)
          @@mutex.synchronize do
            @@connections.each_value do |socket|
              begin
                socket.send(message)
              rescue
                # Manejar errores de envío silenciosamente
              end
            end
          end
        end
  
        # Envía un mensaje a un cliente específico
        def self.send_to_one(identifier : String, message : String)
          if socket = @@connections[identifier]?
            begin
              socket.send(message)
            rescue
              # Manejar errores de envío silenciosamente
            end
          end
        end
  
        # Envía un mensaje a varios clientes específicos
        def self.send_to_many(identifiers : Array(String), message : String)
          identifiers.each do |identifier|
            send_to_one(identifier, message)
          end
        end
  
        # Envía un mensaje a todos los miembros de un grupo
        def self.send_to_group(group_name : String, message : String)
          if group = @@groups[group_name]?
            group.each do |identifier|
              send_to_one(identifier, message)
            end
          end
        end
  
        # Obtiene los miembros de un grupo
        def self.get_group_members(group_name : String) : Set(String)
          @@groups[group_name]? || Set(String).new
        end
  
        # Limpia todas las conexiones y grupos
        def self.clear
          @@mutex.synchronize do
            @@connections.clear
            @@groups.clear
            @@socket_to_identifier.clear
          end
        end
  
        # Obtiene el identificador asociado a un socket
        def self.get_identifier(socket : HTTP::WebSocket) : String?
          @@mutex.synchronize do
            @@socket_to_identifier[socket]
          end
        end
  
        # Obtiene todas las conexiones activas
        def self.all_connections : Array(HTTP::WebSocket)
          @@mutex.synchronize do
            @@connections.values
          end
        end
  
        # Obtiene el número de conexiones activas
        def self.count : Int32
          @@mutex.synchronize { @@connections.size }
        end
      end
    end
  end
  