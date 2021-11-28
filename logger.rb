require './lib/buffering_logger.rb'

class SoftError < StandardError

  attr_reader :obj

  def initialize(msg=nil, obj=nil)
    @obj = obj
    super(msg)
  end

end

class HardError < Exception

  attr_reader :obj

  def initialize(msg=nil, obj=nil)
    @obj = obj
    super(msg)
  end

end

# start in debug if development mode
$log = BufferingLogger.new($stdout, ENV['ENVIRONMENT']=='development' ? BufferingLogger::DEBUG : BufferingLogger::INFO)

Logger = BufferingLogger # compat

# debug/info switch
trap('SIGALRM') do
  if $log.level==BufferingLogger::DEBUG
    $log = BufferingLogger.new($stdout, BufferingLogger::INFO)
  else
    $log = BufferingLogger.new($stdout, BufferingLogger::DEBUG)
  end
end
