require_relative 'base'

Dir['./rack/*'].sort.each { |x| require x }

use Rack::FlushLogBuffer
use Rack::ExceptionHandler

Unreloader.require('app.rb'){'App'}
run(ENV['ENVIRONMENT']=='development' ? Unreloader : App.freeze.app)
