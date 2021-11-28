# If BufferedLogger is used, it doesn't flush it's buffer in the end. Must be done explicitly using this middleware.

raise "BufferedLogger not used? (no flush_buffer! method on $log found)" if ! $log.respond_to?(:flush_buffer!)

module Rack
    class FlushLogBuffer

      def initialize(app, options={})
        @app = app
      end

      def call(env)
        begin
          @app.call(env)
        ensure
          $log.flush_buffer!
        end
      end
      
    end
end