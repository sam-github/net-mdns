#!/usr/local/bin/ruby18 -w
# Author: Sam Roberts <sroberts@uniserve.com>
# Licence: this file is placed in the public domain

$:.unshift(File.dirname($0))

require 'getoptlong'
require 'net/dns/resolvx'
require 'net/dns'

class Resolv
  class DNS
    class Resource
      module IN
        class SRV
          def inspect
            "#{target}:#{port} weight=#{weight} priority=#{priority}"
          end
        end
        class TXT
          def inspect
            strings.inspect
          end
        end
        class PTR
          def inspect
            name.to_s
          end
        end
        class A
          def inspect
            address.to_s
          end
        end
        class HINFO
          def inspect
            "os=#{os.inspect}\ncpu=#{cpu.inspect}"
          end
        end
      end
    end
  end
end

include Net::DNS

$stderr.sync = true
$stdout.sync = true

Addr = '224.0.0.251'
Port = 5353

$id = 1

def ask(name, type)
  $id += 1
  qmsg = Message.new($id)
  qmsg.add_question(name, type)
  @sock.send(qmsg.encode, 0, Addr,Port)
end


@sock = UDPSocket.new

ask(Name.create(ARGV.first || '_http._tcp.local'), IN::PTR)

loop do
  reply, from = @sock.recvfrom(9000)

  puts "++ from #{from.inspect}"

  msg = Resolv::DNS::Message.decode(reply)

  qr = msg.qr==0 ? 'Q' : 'R'
  qrstr = msg.qr==0 ? 'Query' : 'Resp'

  opcode = { 0=>'QUERY', 1=>'IQUERY', 2=>'STATUS'}[msg.opcode]

  puts "#{qrstr}: id #{msg.id} qr #{qr} opcode #{opcode} aa #{msg.aa} tc #{msg.tc} rd #{msg.rd} ra #{msg.ra} rcode #{msg.rcode}"

  msg.question.each do |name, type, unicast|
    puts "qu #{Net::DNS.rrname type} #{name.to_s.inspect} unicast=#{unicast}"
  end
  msg.answer.each do |name, ttl, data, cacheflush|
    puts "an #{Net::DNS.rrname data} #{name.to_s.inspect} ttl=#{ttl} cacheflush=#{cacheflush}"
    puts "   #{data.inspect}"

    case data
    when IN::PTR
      ask(data.name, IN::SRV)
      ask(data.name, IN::TXT)
    when IN::SRV
      ask(data.target, IN::A)
    end
  end
  msg.authority.each do |name, ttl, data, cacheflush|
    puts "au #{Net::DNS.rrname data} #{name.to_s.inspect} ttl=#{ttl} cacheflush=#{cacheflush.inspect}"
    puts "   #{data.inspect}"
  end
  msg.additional.each do |name, ttl, data, cacheflush|
    puts "ad #{Net::DNS.rrname data} #{name.to_s.inspect} ttl=#{ttl} cacheflush=#{cacheflush.inspect}"
    puts "   #{data.inspect}"
  end

  puts
end

