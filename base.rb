Dir.chdir(File.dirname(__FILE__))

require 'bundler'
Bundler.setup
#Bundler.require # always do it on demand, it prevents runtime problems

require 'i18n'
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'
I18n.enforce_available_locales = false

require_relative 'env'

require_relative 'logger'

require 'rack/unreloader'
Unreloader = Rack::Unreloader.new(:subclasses=>%w'Roda Sequel::Model NokoView', :logger=>$log, :reload=>ENV['ENVIRONMENT']=='development' ) {App}

# roda and sequel does require 'roda/plugins/name')
$LOAD_PATH << File.dirname(File.expand_path(__FILE__))

