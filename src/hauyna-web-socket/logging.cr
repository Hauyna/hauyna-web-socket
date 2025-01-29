require "log"

module Hauyna
  module WebSocket
    Log = ::Log.for(self)
    
    class_property log_level : ::Log::Severity = :info
    
    def self.configure_logging
      backend = ::Log::IOBackend.new
      ::Log.setup do |c|
        c.bind "*", log_level, backend
      end
    end
  end
end 