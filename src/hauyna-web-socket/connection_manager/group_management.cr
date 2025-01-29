module Hauyna
  module WebSocket
    module ConnectionManager
      private def self.internal_add_to_group(identifier, group_name)
        @@groups[group_name] ||= Set(String).new
        @@groups[group_name].add(identifier)
      end

      def self.remove_from_group(identifier : String, group_name : String)
        if group = @@groups[group_name]?
          group.delete(identifier)
          @@groups.delete(group_name) if group.empty?
        end
      end

      def self.get_group_members(group_name : String) : Set(String)
        members = @@groups[group_name]?.try(&.dup) || Set(String).new
        puts "Miembros del grupo #{group_name}: #{members.inspect}"
        members
      end

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
    end
  end
end
