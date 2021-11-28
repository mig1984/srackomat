#!/usr/bin/env ruby

# Print log messages human-readable. Used in ./start for instance.
# usage: cat log.txt | tool/logview


# require 'zaml' # better yaml printing than the default yaml
require 'yaml'
require 'colorize'
require 'i18n'
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'
I18n.enforce_available_locales = false

uniqs = {}
uniqs_used = {}

# otherwise complains about broken pipe
trap(:SIGTERM) { exit }
trap(:SIGINT)  { exit }

STDIN.each do |line|
  line.force_encoding("binary")
  
  if line =~ /(\d+\.\d+)\t(debug|info|warn|error|fatal|point)\t(\d+)\t([^:]+):([^#]+)#([^\t]+)\t([^\t]*)(\t\t(.*))?/
    time = Time.at($1.to_f)
    level = $2.to_sym
    thnum = $3
    path = $4
    lineno = $5.to_i
    meth = $6
    msg = $7
    info = $9
    msg.gsub!("\0x00", ' ^ ')
    if info
      begin
        info = YAML::load(info.gsub("\0x00", "\n"))
      rescue Exception
        info = 'CAN NOT RESTORE DUMPED OBJECT, TRY TO USE .inspect() WHILE LOGGING'
      end
    end
    
    result = ''
       
    # message level
    xlevel = level.to_s.upcase.ljust(7)
    xlevel = case level
      when :point
        xlevel.white.on_yellow.bold
      when :debug
        xlevel.bold
      when :info
        xlevel.bold
      when :warn
        xlevel.magenta.bold
      when :error
        xlevel.white.on_red.bold
      when :fatal
        xlevel.white.on_red.bold
    end
    result << xlevel+'| '

    # add time
    time = (time.strftime( "%Y-%m-%d_%H:%M:%S" ) + time.usec.to_s.ljust( 6, '0' ) + ' ')
    if level==:point
      result << time.on_yellow.bold
    else
      result << time
    end
    
    # create unique 3char identifier from a thread num
    if !uniqs[thnum]
      begin
        uniq = (0...3).map { (65 + rand(26)).chr }.join
      end while uniqs_used.has_key?(uniq)
      uniqs_used[uniq] = true
      uniqs[thnum] = uniq
    end
    if level==:point
      result << uniqs[thnum].on_yellow.bold + ' | '
    else
      result << uniqs[thnum].magenta + ' | '
    end
    
    if msg[0,3] == '---'
      # when a message starts with ---, don't prefix it with a location
      if level==:point
        result << msg.on_yellow.bold
      else
        result << msg.magenta
      end
      
    else
      # prefix message with a location
      msg = "#{path}:#{lineno}##{meth}: #{msg}"
      # colorize the message location
      if msg =~ /^(.*?[:!?])( |$)(.*)$/
        place = $1
        rest  = $2.to_s + $3.to_s
        place.gsub!(/:$/,'')
        if level==:point
          place = place.on_yellow.bold
        else
          place = case place
            when /sequel.*log_each/
              place.blue
            when /sequel.*logging/
              place.blue
            when /rack-unreloader/
              place.blue
            when /^app/
              place.light_green
            else
              place.yellow
          end
        end
        msg = place + rest
      end
      result << msg
    end
    
    # dump an additional info
    if info
      s = ''
      if info.is_a?(String)
        s << "\n" + info.split(/\n/).collect { |x| "  | " + x.chomp.green }.join( "\n" )
      elsif info.is_a?( Hash )
        info.each { |k,v|
          s << "\n  -> ".white + k.to_s.light_blue + ":\n"
          if v.is_a?( String ) || v.is_a?( Numeric ) || v===true || !v
            ary = v.to_s.split( "\n" )
          else
            ary = YAML.dump(v).split( "\n" )
            if ary[0] == '--- ' # YAML's ---
              ary.shift
            end
          end
          s << ary.collect { |x| ("     " + x.chomp).green }.join( "\n" )
        }
      else
        s << "\n" + YAML.dump(info).split( "\n" ).collect { |x| ("  | " + x.chomp).green }.join( "\n" )
      end
      result << s
    end
    
    puts result

  else
    puts line
  end
end

