raise "BufferedLogger not used? (no flush_buffer! method on $log found)" if ! $log.respond_to?(:flush_buffer!)

# these are usually defined in init.d/01-base.rb
raise "SoftError not defined" if ! defined? SoftError
raise "HardError not defined" if ! defined? HardError

module Rack
    class ExceptionHandler

      def initialize(app, options={})
        @app = app
      end

      def call(env)
        begin
          @app.call(env)

        rescue SoftError
          
          # print a message, but no backtrace or log buffer
          
          if $!.respond_to?(:obj)
            $log.error("#{$!.class}: #{$!}", $!.obj.inspect)
          else
            $log.error("#{$!.class}: #{$!}")
          end
          
          if ENV['ENVIRONMENT']=='development'
            if env['CONTENT_TYPE'] =~ /^application\/json/
              body = {'class'=>"Error", "message"=>$!.to_s}.to_json
              [ 500, {'Content-Type'=>'application/json'}, [body] ]
            else
              body = "<html><body><h1>500 Error</h1><h2>#{$!}</h2></body></html>"
              [ 500, {'Content-Type'=>'text/html'}, [body] ]
            end
          else
            if env['CONTENT_TYPE'] =~ /^application\/json/
              body = {'class'=>"Error"}.to_json
              [ 500, {'Content-Type'=>'application/json'}, [body] ]
            else
              body = '<html><body><h1>500 Error</h1><h2>Unfortunately an error happened.</h2></body></html>'
              [ 500, {'Content-Type'=>'text/html'}, [body] ]
            end
          end

        rescue HardError, Exception
          
          # print message, the log buffer and backtrace

          $log.print_buffer() if !$log.debug?
          if $!.respond_to?(:obj)
            $log.fatal("#{$!.class}: #{$!}", :backtrace=>$!.backtrace, :info=>$!.obj.inspect)
          else
            $log.fatal("#{$!.class}: #{$!}", $!.backtrace)
          end
          
          if ENV['ENVIRONMENT']=='development'
            if env['CONTENT_TYPE'] =~ /^application\/json/
              body = {'class'=>"Error", "message"=>$!.to_s}.to_json
              [ 500, {'Content-Type'=>'application/json'}, [body] ]
            else
              body = "<html><body><h1>500 Exception Handler</h1><h2>#{$!}</h2><pre>#{$!.backtrace.to_yaml}</pre></body></html>"
              [ 500, {'Content-Type'=>'text/html'}, [body] ]
            end
          else
            if env['CONTENT_TYPE'] =~ /^application\/json/
              body = {'class'=>"Error", 'message'=>''}.to_json
              [ 500, {'Content-Type'=>'application/json'}, [body] ]
            else
              body = '<html><body><h1>500 Exception</h1><h2>Unfortunately an error happened, please try again later.</h2></body></html>'
              [ 500, {'Content-Type'=>'text/html'}, [body] ]
            end
          end
          
        end
        
      end
      
    end
end