require 'net/http'
require 'net/dns/mdns-resolv'
require 'resolv-replace'

# Address lookup

begin
puts Resolv.getaddress('example.local')
rescue Resolv::ResolvError
  puts "no such address!"
end

# Service discovery

#Resolv.mdns.each_resource

mdns = Resolv::MDNS.new

mdns.each_resource('_http._tcp.local', Resolv::DNS::Resource::IN::PTR) do |rrhttp|
  service = rrhttp.name
  host = nil
  port = nil
  path = '/'

  rrsrv = mdns.getresource(rrhttp.name, Resolv::DNS::Resource::IN::SRV)
  host, port = rrsrv.target.to_s, rrsrv.port

  rrtxt = mdns.getresource(rrhttp.name, Resolv::DNS::Resource::IN::TXT)
  path = $1 if  rrtxt.data =~ /path=(.*)/

  http = Net::HTTP.new(host, port)

  headers = http.head(path)

  puts "#{service[0]} on #{host}:#{port}#{path} was last-modified #{headers['last-modified']}"
end

