#!/usr/local/bin/ruby18 -w
# Author: Sam Roberts <sroberts@uniserve.com>
# Licence: this file is placed in the public domain
#
# Advertise a webrick server over mDNS.

require 'webrick'
require 'net/dns/mdns-sd'

DNSSD = Net::DNS::MDNSSD

class HelloServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_GET(req, resp)   
    resp.body = "hello, world\n"
    resp['content-type'] = 'text/plain'
    raise WEBrick::HTTPStatus::OK
  end
end

server = WEBrick::HTTPServer.new( :Port => 8080 )

server.mount( '/hello/', HelloServlet )

handle = DNSSD.register("hello", '_http._tcp', 'local', 8080, 'path' => '/hello/')

['INT', 'TERM'].each { |signal| 
  trap(signal) { server.shutdown; handle.stop; }
}

server.start

