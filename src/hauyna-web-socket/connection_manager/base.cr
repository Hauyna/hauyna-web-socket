require "http/web_socket"
require "json"

module Hauyna
  module WebSocket
    module ConnectionManager
      # Variables de clase compartidas
      @@connections = {} of String => HTTP::WebSocket
      @@socket_to_identifier = {} of HTTP::WebSocket => String
      @@groups = {} of String => Set(String)
      @@operation_channel = ::Channel(ConnectionOperation).new
      @@connection_states = {} of HTTP::WebSocket => ConnectionState
      @@state_timestamps = {} of HTTP::WebSocket => Time
      @@retry_policies = {} of HTTP::WebSocket => RetryPolicy
      @@retry_attempts = {} of HTTP::WebSocket => Int32
      @@state_hooks = {} of Symbol => Array(Proc(HTTP::WebSocket, ConnectionState?, ConnectionState, Nil))
      
      # Mutex para sincronización
      @@mutex = Mutex.new
      
      # Configuración global
      class_property default_retry_policy : RetryPolicy = RetryPolicy.new
      class_property verbose_logging : Bool = false
    end
  end
end 