#!/usr/local/bin/ruby18

require 'socket'
require 'ipaddr'
require 'pp'

require 'net/dns/resolv'

Addr = "224.0.0.251"
Port = 5353

def ip_mreq(maddr, mifx = "0.0.0.0")
  IPAddr.new(maddr).hton + IPAddr.new(mifx).hton
end

class Resolv
  class DNS
    class Name
      def inspect
        to_s + (absolute? ? '.' : '')
      end
    end
  end
end

sock = UDPSocket.new

sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, 1)

sock.bind(Addr, Port)

sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip_mreq(Addr))

loop do

  reply, from = sock.recvfrom(9000)

  if false
    puts "--"
    pp reply
    puts "++"
  end

  msg = Resolv::DNS::Message.decode(reply)

  pp msg

# pp msg.answer
  
end

