#!/usr/bin/ruby

require 'pp'
require 'socket'

require 'resolv'

doslow = false

if doslow

  puts "(builtin) www.google.ca -->"
  addr = IPSocket.getaddress("www.google.ca")
  pp addr

  puts "(resolv) www.google.ca -->"
  addr = Resolv.getaddress("www.google.ca")
  pp addr

  puts "(builtin) ensemble.local -->"
  addr = IPSocket.getaddress("ensemble.local")
  pp addr

  begin
    puts "(resolv) ensemble.local -->"
    addr = Resolv.getaddress("ensemble.local")
    pp addr
  rescue Resolv::ResolvError
  end

  begin
    puts "(builtin) nosuchname.local -->"
    addr = IPSocket.getaddress("nosuchname.local")
    pp addr
  rescue SocketError
  end

  begin
    puts "(resolv) nosuchname.local -->"
    addr = Resolv.getaddress("nosuchname.local")
    pp addr
  rescue Resolv::ResolvError
  end

end

## Now with MultiDNS

require 'multicast'

if doslow

  r = Resolv::MDNS.new(:domain => 'local')

  r.lazy_initialize

  # pp r

  pp r.generate_candidates('foo.')
  pp r.generate_candidates('foo')
  pp r.generate_candidates('foo.com')
  pp r.generate_candidates('foo.local')
  pp r.generate_candidates('foo.bar.local')

end

# pp Resolv.default_resolvers

puts "(resolv+mdns) www.google.ca -->"
addr = Resolv.getaddress("www.google.ca")
pp addr

puts "(resolv+mdns) ensemble.local -->"
addr = Resolv.getaddress("ensemble.local")
pp addr

puts "(resolv+mdns) ensemble.local -->"
addr = Resolv::MDNS.new.getaddress("ensemble.local")
pp addr

=begin
puts "(resolv+mdns) getname #{addr} ->"
name = Resolv.getname(addr)
pp name
=end

puts "(resolv+mdns) getresources _http._tcp.local, ANY ->"
rrs = Resolv::MDNS.new.getresources("_http._tcp.local", Resolv::DNS::Resource::IN::ANY)
pp rrs

begin
  puts "(resolv+mdns) nosuchname.local -->"
  addr = Resolv.getaddress("nosuchname.local")
  pp addr
rescue Resolv::ResolvError
  puts "Nope - no such name!"
end

