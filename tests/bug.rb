#!/usr/bin/ruby

require 'pp'
require 'socket'

puts "(C library resolver) localhost -->"
addr = IPSocket.getaddress("localhost")
pp addr

# This is the default, args = [Resolv::Hosts.new, Resolv::DNS.new]
resolv = Resolv.new

puts "(Hosts, DNS) localhost -->"
addr = resolv.getaddress("localhost")
pp addr
puts "OK - address resolves!"

begin
  puts "(Hosts, DNS) asergh.net -->"
  addr = resolv.getaddress("asergh.net")
  pp addr
rescue
  pp $!
  unless($!.to_s =~ /^no address for/)
    puts "BUG - this should have hit resolv.rb:228, instead it is returning a DNS-specific error!"
  end
end

# This is trying DNS lookup before host lookup
resolv = Resolv.new([Resolv::DNS.new, Resolv::Hosts.new])

begin
  puts "(resolv) localhost -->"
  addr = resolv.getaddresses("localhost")
  pp addr
rescue
  pp $!
  puts "BUG - this failed to find localhost when the resolvers were reordered!"
end

