
require 'resolv'
require 'pp'

conf = Resolv::DNS::Config.new(ARGV.first)

conf.lazy_initialize

pp conf


