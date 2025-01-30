module Hauyna
  module WebSocket
    class WebSocketRoute
      getter path : String
      getter handler : Handler
      getter segments : Array(String)

      def initialize(path : String, handler : Handler)
        @path = path
        @handler = handler
        @segments = path.chomp("/").split("/")
      end

      def match?(request_path : String) : Bool
        req_segments = request_path.chomp("/").split("?").first.split("/")

        return false unless req_segments.size == @segments.size

        @segments.each_with_index.all? do |segment, index|
          segment.starts_with?(":") || segment == req_segments[index]
        end
      end

      def params(request_path : String) : Hash(String, String)
        params = {} of String => String
        req_segments = request_path.chomp("/").split("?").first.split("/")

        @segments.each_with_index do |segment, index|
          if segment.start_with?(":")
            key = segment[1..-1]
            params[key] = req_segments[index]
          end
        end
        params
      end
    end
  end
end
