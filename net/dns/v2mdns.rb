=begin
  Copyright (C) 2005 Sam Roberts

  This library is free software; you can redistribute it and/or modify it
  under the same terms as the ruby language itself, see the file COPYING for
  details.
=end

require 'ipaddr'
require 'resolv'
require 'net/dns/resolvx'
require 'logger'
require 'singleton'

require 'pp'
module Kernel
  def to_pp
    s = PP.pp(self, '')
    s.chomp!
    s
  end
end


BasicSocket.do_not_reverse_lookup = true

class Resolv
  class DNS
    class Message
      # Shouldn't it yield ttl as well? maybe yield data, ttl - will ttl be optional for callers?
      def extract_resources(name, typeclass)
        msg = self
        if typeclass < DNS::Resource::ANY
          n0 = DNS::Name.create(name)
          msg.each_answer {|n, ttl, data|
            yield n, ttl, data if n0 == n
          }
        end
        yielded = false
        n0 = DNS::Name.create(name)
        msg.each_answer {|n, ttl, data|
          if n0 == n
            case data
            when typeclass
              yield n, ttl, data
              yielded = true
            when DNS::Resource::CNAME
              n0 = data.name
            end
          end
        }
        return if yielded
        msg.each_answer {|n, ttl, data|
          if n0 == n
            case data
            when typeclass
              yield n, ttl, data
            end
          end
        }
      end
    end
  end
end

module Net
  module DNS

    Message      = Resolv::DNS::Message
    Name         = Resolv::DNS::Name
    DecodeError  = Resolv::DNS::DecodeError

    module RR
      ANY = Resolv::DNS::Resource::IN::ANY
      SRV = Resolv::DNS::Resource::IN::SRV
      PTR = Resolv::DNS::Resource::IN::PTR
      TXT = Resolv::DNS::Resource::IN::TXT
      A   = Resolv::DNS::Resource::IN::A
    end

    module MDNS

      Answer = Struct.new(:name, :ttl, :data)

      class Answer
        def inspect
          case data
          when RR::A
            "#{name.inspect} (#{ttl}) -> A   #{data.address.to_s}"
          when RR::PTR
            "#{name.inspect} (#{ttl}) -> PTR #{data.name}"
          when RR::SRV
            "#{name.inspect} (#{ttl}) -> SRV #{data.target}:#{data.port}"
          when RR::TXT
            "#{name.inspect} (#{ttl}) -> TXT #{data.strings.inspect}"
          else
            "#{name.inspect} (#{ttl}) -> ??? #{data.inspect}"
          end
        end
      end

      class Responder
        include Singleton

        # mDNS network params
        Addr = "224.0.0.251"
        Port = 5353
        UDPSize = 9000

        attr_reader :thread

        def initialize
          @queries = []

          @mutex = Mutex.new

          @log = Logger.new(STDOUT)
          @log.level = Logger::DEBUG

          @log.debug( "start" )

          @sock = UDPSocket.new
          @sock.fcntl(Fcntl::F_SETFD, 1)

          # Join the multicast group.
          @sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, 1)
# TODO    #@sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEPORT, 1)
          @sock.bind(Addr, Port)
          # make a struct ip_mreq { struct in_addr, struct in_addr }
          ip_mreq =  IPAddr.new(Addr).hton + IPAddr.new("0.0.0.0").hton
          @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip_mreq)

          @thread = Thread.new do
            responder_loop
          end
        end

        def responder_loop
          loop do
            # TODO - does io need to be synchronized?
            reply, from = @sock.recvfrom(UDPSize)

            @log.debug( "recv from=#{from.inspect} len=#{reply.length}" )

            begin
              msg =  Message.decode(reply)

              next if msg.qr == 0

              @log.debug( 'received answers:' )

              msg.each_answer do |n, ttl, data|
                @log.debug( "++  #{ Answer.new(n, ttl, data).inspect }" )
              end


              @mutex.synchronize do
                
                @log.debug( "active queries=#{@queries.length}" )

                @queries.each do |q|
                  answers = []

                  if( q.name.to_s == '*' )
                    msg.each_answer { |n, ttl, data| answers.push [ n, ttl, data] }
                  else
                    msg.extract_resources(q.name, q.type) { |n, ttl, data| answers.push [n, ttl, data] }
                  end

                  @log.debug( "query: #{q.name.inspect}:#{q.type} is pushed #{answers.length}" )

                  if( answers.first )
                    q.queue.push(answers.map { |a| Answer.new(*a) } )
                  end
                end
              end
            rescue DecodeError
              @log.warn( "mDNS decode error: #{reply.inspect}" )
            end
          end
        end

        def send(msg)
          if( msg.is_a?(Message) )
            msg = msg.encode
          else
            msg = msg.to_str
          end

          # TODO - ensure this doesn't cause DNS lookup for a dotted IP
          @sock.send(msg, 0, Addr, Port)
        end



        def start(query)
          @mutex.synchronize do
            begin
              # TODO - return cached responses
              @queries << query

              # '*' is a pseudo-query, it will match any Answers, but can't be used
              # to send a Query.
              if( query.name.to_s != '*' )
                #             pp query
                qmsg = Message.new
                qmsg.rd = 0
                qmsg.add_question(query.name, query.type)
                #             pp qmsg
                send(qmsg)
              end
            rescue
              @log.warn( "start failed: #{$!}" )
              @queries.delete(query)
              raise
            end
          end
        end

        def stop(query)
          @mutex.synchronize do
            @log.debug( "stop query: #{query.inspect}" )
            @queries.delete(query)
          end
        end

      end # Responder


      class Query
        attr_reader :name, :type, :queue

        def initialize(name, type = RR::ANY, &proc)
          @name = Name.create(name)
          @type = type
          @queue = Queue.new

          Responder.instance.start(self)

          @thread = Thread.new do
            begin
              loop do
                answers = @queue.pop

                proc.call(self, answers)
              end
            rescue
              # This is noisy, but better than silent failure. If you don't want
              # me to print your exceptions, make sure they don't get out of your
              # Proc!
              $stderr.puts "query #{self} yield raised #{$!}"
            ensure
              Responder.instance.stop(self)
            end
          end
        end

        def stop
          @thread.stop
        end
      end # Query

    end
  end
end

include Net::DNS

# I don't want lines of this report intertwingled.
$print_mutex = Mutex.new

def print_answers(q,answers)
  $print_mutex.synchronize do
    puts "query #{q.name}/#{q.type} got #{answers.length} answers:"
    answers.each do |a|
      case a.data
      when Net::DNS::RR::PTR
        puts "  #{a.name} -> PTR #{a.data.name}"
      when Net::DNS::RR::SRV
        puts "  #{a.name} -> SRV #{a.data.target}:#{a.data.port}"
      when Net::DNS::RR::TXT
        puts "  #{a.name} -> TXT"
        a.data.strings.each { |s| puts "    #{s}" }
      else
        puts "  #{a.name} -> ??? #{a.data.inspect}"
      end
    end
  end
end

Net::DNS::MDNS::Query.new('*') do |q, answers|
  print_answers(q, answers)
end

# FIXME - I don't get my queries answered!

Net::DNS::MDNS::Query.new('_http._tcp.local.', Resolv::DNS::Resource::IN::ANY) do |q, answers|
  print_answers(q, answers)
end

Net::DNS::MDNS::Responder.instance.thread.join

