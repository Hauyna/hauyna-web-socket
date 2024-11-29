module Hauyna
  module WebSocket
    class WebSocketRoute
      property path : String
      property handler : Handler
      property segments : Array(String)

      def initialize(@path, @handler)
        @segments = path.chomp("/").split("/")
      end

      def match?(request_path : String) : Bool
        req_segments = request_path.chomp("/").split("/")
        return false unless req_segments.size == @segments.size

        @segments.each_with_index.all? do |segment, index|
          segment.starts_with?(":") || segment == req_segments[index]
        end
      end

      def params(request_path : String) : Hash(String, String)
        params = {} of String => String
        req_segments = request_path.chomp("/").split("/")

        @segments.each_with_index do |segment, index|
          if segment.starts_with?(":")
            key = segment[1..-1]
            params[key] = req_segments[index]
          end
        end
        params
      end
    end
  end
end
