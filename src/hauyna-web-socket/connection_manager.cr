require "http/web_socket"

module Hauyna
    module WebSocket
      module ConnectionManager
        @@connections = {} of String => HTTP::WebSocket
        @@socket_to_identifier = {} of HTTP::WebSocket => String
        @@groups = {} of String => Set(String)
        @@mutex = Mutex.new
  
        # Registra una nueva conexión con su identificador
        def self.register(socket : HTTP::WebSocket, identifier : String)
          @@mutex.synchronize do
            @@connections[identifier] = socket
            @@socket_to_identifier[socket] = identifier
          end
        end
  
        # Desregistra una conexión y limpia sus grupos asociados
        def self.unregister(socket : HTTP::WebSocket)
          @@mutex.synchronize do
            if identifier = @@socket_to_identifier[socket]?
              @@connections.delete(identifier)
              @@socket_to_identifier.delete(socket)
              
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
  
        # Añade un usuario a un grupo específico
        def self.add_to_group(identifier : String, group_name : String)
          @@mutex.synchronize do
            @@groups[group_name] ||= Set(String).new
            @@groups[group_name].add(identifier)
            puts "Grupo #{group_name} actualizado: #{@@groups[group_name].inspect}"
          end
        end
  
        def self.remove_from_group(identifier : String, group_name : String)
          @@mutex.synchronize do
            if group = @@groups[group_name]?
              group.delete(identifier)
              @@groups.delete(group_name) if group.empty?
            end
          end
        end
  
        def self.broadcast(message : String)
          @@mutex.synchronize do
            @@connections.each_value do |socket|
              begin
                socket.send(message)
              rescue
              end
            end
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
          if group = @@groups[group_name]?
            group.each do |identifier|
              send_to_one(identifier, message)
            end
          end
        end
  
        def self.get_group_members(group_name : String) : Set(String)
          members = @@mutex.synchronize { @@groups[group_name]? || Set(String).new }
          puts "Miembros del grupo #{group_name}: #{members.inspect}"
          members
        end
  
        def self.clear
          @@mutex.synchronize do
            @@connections.clear
            @@groups.clear
            @@socket_to_identifier.clear
          end
        end
  
        def self.get_identifier(socket : HTTP::WebSocket) : String?
          @@mutex.synchronize do
            @@socket_to_identifier[socket]
          end
        end
  
        def self.all_connections : Array(HTTP::WebSocket)
          @@mutex.synchronize do
            @@connections.values
          end
        end
  
        def self.count : Int32
          @@mutex.synchronize { @@connections.size }
        end
  
        # Obtener todos los grupos a los que pertenece un usuario
        def self.get_user_groups(identifier : String) : Array(String)
          @@mutex.synchronize do
            groups = [] of String
            @@groups.each do |group_name, members|
              if members.includes?(identifier)
                groups << group_name
              end
            end
            groups
          end
        end
  
        def self.is_in_group?(identifier : String, group_name : String) : Bool
          @@mutex.synchronize do
            if group = @@groups[group_name]?
              group.includes?(identifier)
            else
              false
            end
          end
        end
      end
    end
  end
  