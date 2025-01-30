module Hauyna
  module WebSocket
    module ConnectionManager
      class RetryPolicy
        property max_attempts : Int32
        property base_delay : Time::Span
        property max_delay : Time::Span
        property backoff_multiplier : Float64
        property jitter : Float64

        def initialize(
          @max_attempts = 5,
          @base_delay = 1.seconds,
          @max_delay = 30.seconds,
          @backoff_multiplier = 2.0,
          @jitter = 0.1,
        )
        end

        def calculate_delay(attempt : Int32) : Time::Span
          return max_delay if attempt >= max_attempts

          delay = base_delay * (backoff_multiplier ** attempt)
          jitter_amount = delay * jitter
          delay += Random.rand(-jitter_amount.total_seconds..jitter_amount.total_seconds).seconds

          [delay, max_delay].min
        end
      end

      def self.set_retry_policy(socket : HTTP::WebSocket, policy : RetryPolicy)
        @@retry_policies[socket] = policy
        @@retry_attempts[socket] = 0
      end

      private def self.handle_retry(socket : HTTP::WebSocket)
        return unless policy = @@retry_policies[socket]?
        attempts = @@retry_attempts[socket] ||= 0

        if attempts < policy.max_attempts
          delay = policy.calculate_delay(attempts)
          @@retry_attempts[socket] += 1

          spawn do
            sleep delay
            if valid_transition?(ConnectionState::Error, ConnectionState::Reconnecting)
              set_connection_state(socket, ConnectionState::Reconnecting)
            end
          end
        end
      end
    end
  end
end
