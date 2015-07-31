require 'bundler/setup'
require 'omniauth-infusionsoft'
require './app.rb'

use Rack::Session::Cookie, :secret => 'abc123'

use OmniAuth::Builder do
  provider :infusionsoft, ENV['APP_ID'], ENV['APP_SECRET'], :scope => 'email,read_stream'
end

run Sinatra::Application
