# All messages are buffered, the buffer has to be flushed explicitly.
# Those with loglevel>=minimal are displayed directly.

require 'yaml'

class BufferingLogger

  # compat
  module Severity
  end
  
  # compat
  class Formatter
  end
  
  # compat
  LogDevice = $stdout.class

  DEBUG  = 1
  INFO   = 2
  WARN   = 3
  ERROR  = 4
  FATAL  = 5
  POINT  = 6
  NOOUT  = 7
  
  class << self
    attr_accessor :mutex
  end
  
  attr_reader :level

  def initialize(output, level=DEBUG, path_strip=File.dirname(File.dirname(__FILE__)))
    self.class.mutex ||= Mutex.new
    @strip_length = path_strip.length+1
    @output = output || $stdout
    @output.sync = true
    @level = level
    @buffers = {}

    level <= DEBUG ? define_enabled(:debug) : define_disabled(:debug)
    level <= INFO  ? define_enabled(:info) : define_disabled(:info)
    level <= WARN  ? define_enabled(:warn) : define_disabled(:warn)
    level <= ERROR ? define_enabled(:error) : define_disabled(:error)
    level <= FATAL ? define_enabled(:fatal) : define_disabled(:fatal)
    level <= POINT ? define_enabled(:point) : define_disabled(:point)

  end

  def buffer
    @buffers[Thread.current] ||= ''
  end

  def print_buffer()
    begin
      self.class.mutex.synchronize {
        @output.print(buffer)
      }
    rescue Errno::EPIPE
    end
  end
  
  def flush_buffer!
    @buffers.delete(Thread.current)
  end
  
  private
  
  def define_disabled(name)
    define_singleton_method(name) do |*args|
      mkentry( name, *args)
    end
    define_singleton_method("#{name}?") { false }
  end

  def define_enabled(name)
    define_singleton_method(name) do |*args|
      output = mkentry( name, *args)
      begin
        self.class.mutex.synchronize {
          @output.puts( output )
        }
      rescue Errno::EPIPE
      rescue ThreadError
        # called from a trap context
        begin
          @output.puts( output )
        rescue Errno::EPIPE
        end
      end
    end
    define_singleton_method("#{name}?") { true }
  end
  
  def deep_normalize( obj=self, normalized={} )
    if normalized.has_key?( obj.object_id )
      return normalized[obj.object_id]
    else
      begin
        cl = obj.clone
      rescue Exception
        # unclonnable (TrueClass, Fixnum, ...)
        normalized[obj.object_id] = obj
        return obj
      else
        normalized[obj.object_id] = cl
        normalized[cl.object_id] = cl
        if cl.is_a?( Hash )
          cl2 = Hash.new
          cl.each { |k,v| cl2[k] = deep_normalize( v, normalized ) }
          cl = cl2
        elsif cl.is_a?( Array )
          cl2 = Array.new
          cl.each { |v| cl2 << deep_normalize( v, normalized ) }
          cl = cl2
        end
        cl.instance_variables.each do |var|
          v = cl.instance_eval( var )
          v_cl = deep_normalize( v, normalized )
          cl.instance_eval( "#{var} = v_cl" )
        end
        return cl
      end
    end
  end
  
  def mkentry( name, msg, info=nil)
    # if the message is not a string, try to inspect the object
    if !msg.is_a?( String )
      msg = ""<<msg.inspect
    else
      msg = ""<<msg  # "unfreezing" string if frozen
    end

    # replace newlines
    msg.gsub!(/\n/, "\0x00")

    # get file location
    c = caller_locations(2,1)
    if c && c.first
      path = c.first.absolute_path[@strip_length..-1]
      lineno = c.first.lineno.to_s
      meth = c.first.base_label
    else
      path = '?'
      lineno = '?'
      meth = '?'
    end
    
    # if there is an additional info, dump it (but not all types of objects, otherwise can't be unmarshalled)
    if info
      if !info.is_a?(Hash) && !info.is_a?(String) && !info.is_a?(Numeric)
        info = info.inspect
      end
      if info.is_a?(Hash) && info.class!=Hash
        info = deep_normalize(info) # otherwise not restorable
      end
      info = "\t\t" + info.to_yaml.gsub(/\n/, "\0x00")
    end
    
    entry = "#{Time.now.to_f}\t#{name}\t#{Thread.current.object_id}\t#{path}:#{lineno}##{meth}\t#{msg}#{info}\n"
    
    # save the log entry into a buffer
    entry.force_encoding 'UTF-8'

    buffer << entry
    
    entry
  end

end

