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
$stdout.sync = true
$stderr.sync = true

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

      class Answer
        # TOA - time of arrival (of an answer)
        attr_reader :toa, :name, :ttl, :data

        def initialize(name, ttl, data)
          @name = name
          @ttl = ttl
          @data = data
          @toa = Time.now
        end

        def type
          data.class
        end

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

      # TODO - Will need to synchronize access!!!
      class Cache
        # asked: Hash[Name] -> Hash[Resource] -> Time (that question was asked)
        attr_reader :asked

        # asked: Hash[Name] -> Hash[Resource] -> Array -> Answer (answers to value/resource)
        attr_reader :cached

        def initialize
          @asked = Hash.new { |h,k| h[k] = Hash.new }

          @cached = Hash.new { |h,k| h[k] = (Hash.new { |a,b| a[b] = Array.new }) }
        end

        def cache_question(name, type)
          @asked[name][type] = Time.now
        end

        def cache_answer(answer)
          # FIXME - don't duplicate answers, and flush answers if mdnsbit is set!
          @cached[answer.name][answer.type] << answer
        end

        def answers_for(name, type)
          @cached[name][type]
        end

        def asked?(name, type)
          t = @asked[name][type] || @asked[name][RR::ANY]

          # TODO - true if (Time.now - t) < some threshold...

          t
        end

      end

      class Responder
        include Singleton

        # mDNS network params
        Addr = "224.0.0.251"
        Port = 5353
        UDPSize = 9000

        attr_reader :thread
        attr_reader :cache

        def initialize
          @mutex = Mutex.new

          @cache = Cache.new

          @queries = []

          @log = Logger.new(STDERR)
          @log.level = Logger::DEBUG

          @log.debug( "start" )

          kINADDR_IFX = Socket.gethostbyname(Socket.gethostname)[3]

          @sock = UDPSocket.new

          # TODO - do we need this?
          @sock.fcntl(Fcntl::F_SETFD, 1)

          # Allow 5353 to be shared.
          begin
            @sock.setsockopt(Socket::SOL_SOCKET, 0x0200, 1)
          rescue
            @log.warn( "set SO_REUSEPORT raised #{$!}, try SO_REUSEADDR" )
            @sock.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, 1)
          end

          # Request dest addr and ifx ids... no.

          # Join the multicast group.
          #  option is a struct ip_mreq { struct in_addr, struct in_addr }
          ip_mreq =  IPAddr.new(Addr).hton + kINADDR_IFX
          @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip_mreq)
          @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, kINADDR_IFX)

          # Set IP TTL for outgoing packets.
          # @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, 255)

          # @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, 255 as int)
          #  - or -
          # @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, 255 as byte)

          # Bind to our port.
          @sock.bind(Socket::INADDR_ANY, Port)

          @thread = Thread.new do
            responder_loop
          end
        end

        def responder_loop
          loop do
            # from is [ AF_INET, port, name, addr ]
            reply, from = @sock.recvfrom(UDPSize)

            begin
              msg =  Message.decode(reply)

              @log.debug( "from #{from[3]}:#{from[1]} -> qr=#{msg.qr} qcnt=#{msg.question.size} acnt=#{msg.answer.size}" )


              # When we see a QM:
              #  - record the question as asked
              #  - flush any answers we have?
              if( msg.query? )
                msg.each_question do |name, type|
                  # Skip QUs
                  next if (type::ClassValue >> 15) == 1
                  @cache.cache_question(name, type)
                  @log.debug( "cache - add q #{name.inspect}/#{type.to_s} from net" )
                end

                next
              end

              # Cache answers
              msg.each_answer do |n, ttl, data|
                a = Answer.new(n, ttl, data)
                @cache.cache_answer(a)
                @log.debug( "++  #{ a.inspect }" )
              end

              @mutex.synchronize do
                
#               @log.debug( "active queries=#{@queries.length}" )

                @queries.each do |q|
                  answers = []

                  if( q.name.to_s == '*' )
                    msg.each_answer { |n, ttl, data| answers.push [ n, ttl, data] }
                  else
                    msg.extract_resources(q.name, q.type) { |n, ttl, data| answers.push [n, ttl, data] }
                  end

                  @log.debug( "push #{answers.length} to #{q.inspect}" )

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



        # '*' is a pseudo-query, it will match any Answers, but can't be used
        # to send a Query.
        #
        # Cached answers will be pushed right away.
        #
        # Query will be sent to the net if it hasn't already been asked.
        #
        # TODO - try to send with "unicast response" bit set.
        def start(query)
          @mutex.synchronize do
            begin
              # TODO - return cached responses
              @queries << query

              if( query.name.to_s != '*' )
                asked = @cache.asked?(query.name, query.type)
                answers = @cache.answers_for(query.name, query.type)

                @log.debug( "query #{query.inspect} - start asked?=#{asked ? "y" : "n"} answers#=#{answers.size}" )
               
                unless asked
                  qmsg = Message.new
                  qmsg.rd = 0
                  qmsg.add_question(query.name, query.type)
                  
                  send(qmsg)
                end

                query.push answers if answers.first
              end
            rescue
              @log.warn( "query #{query.inspect} - start failed: #{$!}" )
              @queries.delete(query)
              raise
            end
          end
        end

        def stop(query)
          @mutex.synchronize do
            @log.debug( "query #{query.inspect} - stop" )
            @queries.delete(query)
          end
        end

      end # Responder


      # TODO - three kinds of Query
      #  - one is just a handle around a Queue, you have to call #pop
      #    to get answers
      #  - derived is one that calls proc in current thread
      #  - also derived is one that calls proc in new thread, like DNS-SD?
      class Query
        attr_reader :name, :type, :queue

        def push(*args)
          queue.push(*args)
        end

        def to_s
          "q?#{name}/#{type.to_s.gsub(/Resolv::DNS::Resource::/, '')}"
        end

        def inspect
          to_s + "(#{queue.length})"
        end

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
      when RR::A
        puts "  #{a.name} -> A   #{a.data.address.to_s}"
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

=begin
Net::DNS::MDNS::Query.new('*') do |q, answers|
  print_answers(q, answers)
end
=end

Net::DNS::MDNS::Query.new('_http._tcp.local.', Resolv::DNS::Resource::IN::ANY) do |q, answers|
  print_answers(q, answers)
end


Net::DNS::MDNS::Query.new('_ftp._tcp.local.', Resolv::DNS::Resource::IN::ANY) do |q, answers|
  print_answers(q, answers)
end

sleep 10

Net::DNS::MDNS::Query.new('_ftp._tcp.local.', Resolv::DNS::Resource::IN::ANY) do |q, answers|
  print_answers(q, answers)
end

Net::DNS::MDNS::Query.new('_daap._tcp.local.', Resolv::DNS::Resource::IN::ANY) do |q, answers|
  print_answers(q, answers)
end

Net::DNS::MDNS::Responder.instance.thread.join

