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
        attr_reader :name, :ttl, :data, :toa, :retries
        attr_writer :retries

        def initialize(name, ttl, data)
          @name = name
          @ttl = ttl
          @data = data
          @toa = Time.now.to_i
          @retries = 0
        end

        def type
          data.class
        end

        def refresh
          # Percentage points are from mDNS
          percent = [80,85,90,95][retries]

          # TODO - add a 2% of TTL jitter
          toa + ttl * percent / 100 if percent
        end

        def expiry
          toa + (ttl == 0 ? 1 : ttl)
        end

        def expired?
          true if Time.now.to_i > expiry
        end

        def absolute?
          @data.cacheflush?
        end

        # TODO - should be to_s, so inspect can give all attributes?
        def inspect
          flags = ''
          flags << '!' if absolute?
          flags << '-' if ttl == 0
          case data
          when RR::A
            "#{name.to_s} (#{ttl}) -> #{flags} A   #{data.address.to_s}"
          when RR::PTR
            "#{name.to_s} (#{ttl}) -> #{flags} PTR #{data.name}"
          when RR::SRV
            "#{name.to_s} (#{ttl}) -> #{flags} SRV #{data.target}:#{data.port}"
          when RR::TXT
            "#{name.to_s} (#{ttl}) -> #{flags} TXT #{data.strings.inspect}"
          else
            "#{name.to_s} (#{ttl}) -> #{flags} ??? #{data.inspect}"
          end
        end
      end

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

        # Return cached answer, or nil if answer wasn't cached.
        def cache_answer(an)
          answers = @cached[an.name][an.type]

          if( an.absolute? )
            # Replace answers older than a ~1 sec [mDNS]
            now_m1 = Time.now.to_i - 1
            answers.delete_if { |a| a.toa < now_m1 }
          end

          old_an = answers.detect { |a| a.name == an.name && a.data == an.data }

          if !old_an
            answers << an
          else
            if( an.ttl == 0 || an.expiry > old_an.expiry)
              answers.delete( old_an )
              answers << an
            else
              an = nil
            end
          end

          an
        end

        def answers_for(name, type)
          answers = []
          if( name.to_s == '*' )
            @cached.keys.each { |n| answers += answers_for(n, type) }
          elsif( type == RR::ANY )
            @cached[name].each { |rtype,rdata| answers += rdata }
          else
            answers += @cached[name][type]
          end
          answers
        end

        def asked?(name, type)
          return true if name.to_s == '*'

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
        attr_reader :log

        def debug(*args)
          @log.debug( *args )
        end
        def warn(*args)
          @log.warn( *args )
        end
        def error(*args)
          @log.error( *args )
        end

        def initialize
          @log = Logger.new(STDERR)
          @log.level = Logger::DEBUG

          @mutex = Mutex.new

          @cache = Cache.new

          @queries = []

          @log.debug( "start" )

          kINADDR_IFX = Socket.gethostbyname(Socket.gethostname)[3]

          @sock = UDPSocket.new

          # TODO - do we need this?
          @sock.fcntl(Fcntl::F_SETFD, 1)

          # Allow 5353 to be shared.
          so_reuseport = 0x0200 # The definition on OS X, where it is required.
          if Socket.constants.include? 'SO_REUSEPORT'
            so_reuseport = Socket::SO_REUSEPORT
          end
          begin
            @sock.setsockopt(Socket::SOL_SOCKET, so_reuseport, 1)
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

          # Start resonder and cacheing threads.

          @waketime = nil

          @sweep_thrd = Thread.new do
            sweep_loop
          end

          @thread = Thread.new do
            responder_loop
          end
        end

        def responder_loop
          loop do
            # from is [ AF_INET, port, name, addr ]
            reply, from = @sock.recvfrom(UDPSize)

            @mutex.synchronize do

              begin
                msg =  Message.decode(reply)

                @log.debug( "from #{from[3]}:#{from[1]} -> qr=#{msg.qr} qcnt=#{msg.question.size} acnt=#{msg.answer.size}" )

                # When we see a QM:
                #  - record the question as asked
                #  - TODO flush any answers we have over 1 sec old (otherwise if a machine goes down, its
                #    answers stay until there ttl, which can be very long!)
                if( msg.query? )
                  msg.each_question do |name, type|
                    # Skip QUs
                    next if (type::ClassValue >> 15) == 1
                    @log.debug( "++ q #{name.to_s}/#{type.to_s.sub(/.*source::/,'')}" )
                      @cache.cache_question(name, type)
                  end

                  next
                end

                # Cache answers
                msg.each_answer do |n, ttl, data|
                  a = Answer.new(n, ttl, data)
                  @log.debug( "++ a #{ a.inspect }" )
                  a = @cache.cache_answer(a)

                  if a
                    # wake sweeper if cached answer needs refreshing before current waketime
                    if( !@waketime || a.refresh < @waketime )
                      @waketime = a.refresh
                      @sweep_thrd.wakeup
                    end
                  end
                end

                # Push answers to Queries
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

              rescue DecodeError
                @log.warn( "decode error: #{reply.inspect}" )
              end

            end # end sync
          end # end loop
        end

        def sweep_loop
          delay = 0

          loop do

            if delay > 0
              sleep(delay)
            else
              sleep
            end

            @mutex.synchronize do
              debug( "sweep begin" )

              @waketime = nil

              questions = Message.new(0)
              now = Time.now.to_i

              # next Answer needing refresh
              sweep = nil

              @cache.cached.each do |name,rtypes|
                qtype = []

                rtypes.each do |rtype, answers|
                  answers.delete_if do |a|
                    r = a.expired?
                    debug( "-- a #{a.inspect}" ) if r
                    r
                  end
                  answers.each do |a|
                    if a.refresh
                      if now >= a.refresh
                        a.retries += 1
                        qtype << a.data.class
                      end
                      if !sweep || a.refresh < sweep.refresh
                        sweep = a
                      end
                    end
                  end
                end

                qtype.uniq.each do |q|
                  debug( "-> q #{name} #{q.to_s.sub(/.*source::/, '')}" )
                  questions.add_question(name, q)
                end
              end

              send(questions) if questions.question.first

              @waketime = sweep.refresh if sweep

              if @waketime
                delay = @waketime - Time.now.to_i
                delay = 1 if delay < 1
              else
                delay = 0 # forever (until Thread#wake)
              end

              debug( "refresh in #{delay} sec for #{sweep.inspect}" )

              debug( "sweep end" )
            end
          end # end loop
        end

        def send(msg)
          if( msg.is_a?(Message) )
            msg = msg.encode
          else
            msg = msg.to_str
          end

          # TODO - ensure this doesn't cause DNS lookup for a dotted IP
          begin
            @sock.send(msg, 0, Addr, Port)
          rescue
            @log.error( "send msg failed: #{$!}" )
            raise
          end
        end

        # 

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
              @queries << query

              asked = @cache.asked?(query.name, query.type)
              answers = @cache.answers_for(query.name, query.type)

              @log.debug( "query #{query.inspect} - start asked?=#{asked ? "y" : "n"} answers#=#{answers.size}" )
             
              unless asked
                qmsg = Message.new(0)
                qmsg.rd = 0
                qmsg.add_question(query.name, query.type)
                
                send(qmsg)
              end

              query.push answers if answers.first
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


      #  - derived is one that calls proc in current thread
      class Query
        attr_reader :name, :type, :queue

        def push(*args)
          @queue.push(*args)
        end

        def pop
          @queue.pop
        end

        def length
          @queue.length
        end

        def to_s
          "q?#{name}/#{type.to_s.sub(/.*source::/, '')}"
        end

        def inspect
          to_s + "(#{@queue.length})"
        end

        def initialize(name, type = RR::ANY)
          @name = Name.create(name)
          @type = type
          @queue = Queue.new

          Responder.instance.start(self)
        end

        def stop
          Responder.instance.stop(self)
        end
      end # Query

      class BackgroundQuery < Query
        def initialize(name, type = RR::ANY, &proc)
          super(name, type)

          @thread = Thread.new do
            begin
              loop do
                answers = self.pop

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
      end # BackgroundQuery

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
MDNS::BackgroundQuery.new('*') do |q, answers|
  print_answers(q, answers)
end
=end

MDNS::BackgroundQuery.new('_http._tcp.local.', RR::PTR) do |q, answers|
  print_answers(q, answers)
end

MDNS::BackgroundQuery.new('_ftp._tcp.local.', RR::ANY) do |q, answers|
  print_answers(q, answers)
end

sleep 4

MDNS::BackgroundQuery.new('_ftp._tcp.local.', RR::ANY) do |q, answers|
  print_answers(q, answers)
end

MDNS::BackgroundQuery.new('_daap._tcp.local.', RR::ANY) do |q, answers|
  print_answers(q, answers)
end

MDNS::BackgroundQuery.new('ensemble.local.', RR::A) do |q, answers|
  print_answers(q, answers)
end

Signal.trap('USR1') do
  PP.pp( MDNS::Responder.instance.cache, $stderr )
end

sleep

