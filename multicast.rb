# $Id: $

require 'resolv'


class Resolv
  class DNS
    class Resource
      module IN

        # SRV RR format defined in RFC 2782
        class SRV < Resource
          ClassHash[[TypeValue = 33, ClassValue = ClassValue]] = self

          def initialize(priority, weight, port, target)
            @priority = priority.to_int
            @weight = weight.to_int
            @port = port.to_int
            @target = Name.create(target)
          end
          attr_reader :priority, :weight, :port, :target

          def encode_rdata(msg)
            msg.put_pack("n", @priority)
            msg.put_pack("n", @weight)
            msg.put_pack("n", @port)
            msg.put_name(@target)
          end

          def self.decode_rdata(msg)
            priority, = msg.get_unpack("n")
            weight,   = msg.get_unpack("n")
            port,     = msg.get_unpack("n")
            target    = msg.get_name
            return self.new(priority, weight, port, target)
          end

          def inspect
            "IN::SRV priority=#{priority} weight=#{weight} target=#{target}:#{port}"
          end
        end

      end
    end
  end
end


class Resolv
  # The default resolvers. They default to:
  #   [Hosts.new, DNS.new]
  #
  # To enable mDNS with the default resolvers, do:
  #   Resolv.default_resolvers.push( Resolv::MDNS.new )
  #
  def self.default_resolvers
    DefaultResolver.resolvers
  end

  # The resolvers supported.
  attr_reader :resolvers

  class DNS
    class Config
      attr_reader :ndots
      attr_reader :search
    end
    class Name
      def inspect
        to_s
      end

      # self is <= +name+ if the last labels are the same as name
      #   foo.example.com < example.com # -> true
      #   example.com < example.com # -> true
      #   com < example.com # -> false
      #   bar.com < example.com # -> false
      def <=(name)
        n = name.to_s

        self.to_s =~ /#{n}$/
      end
    end
  end
end


class Resolv
  class MDNS
    # draft-chesire-dnsex-multicastdns-01.txt
    #
    # Extends "normal" DNS to link-local multicast.
    #
    # STD0013 (RFC 1035, etc.)
    # ftp://ftp.isi.edu/in-notes/iana/assignments/dns-parameters

    # link-local multicast
    Addr = "224.0.0.251"
    Port = 5353
    UDPSize = 9000
    # TODO - Orig=512, set to 9000?

    def initialize(config_info=nil)
      @mutex = Mutex.new
      @config = DNS::Config.new(config_info)
      @initialized = nil
    end

    def lazy_initialize
      @mutex.synchronize {
        unless @initialized
          @config.lazy_initialize

          @requester = MulticastUDP.new

          @initialized = true
        end
      }
    end

    # TODO - this name/address/resource trio - can it be factored into a module,
    # so we can include it from resolv.rb?
    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    def each_address(name)
      each_resource(name, DNS::Resource::IN::A) {|resource| yield resource.address}
    end

    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("DNS result has no information for #{address}")
    end

    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    def each_name(address)
      case address
      when DNS::Name
        ptr = address
      when IPv4::Regex
        ptr = IPv4.create(address).to_name
      when IPv6::Regex
        ptr = IPv6.create(address).to_name
      else
        raise ResolvError.new("cannot interpret as address: #{address}")
      end
      each_resource(ptr, DNS::Resource::IN::PTR) {|resource| yield resource.name}
    end

    def getresource(name, typeclass)
      each_resource(name, typeclass) {|resource| return resource}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    def getresources(name, typeclass)
      ret = []
      each_resource(name, typeclass) {|resource| ret << resource}
      return ret
    end

    def generate_candidates(name)
      # Names ending in .local MUST be resolved using mDNS. Other names may be, but
      # SHOULD NOT be, so a local machine can't spoof a non-local address.
      #
      # Reverse lookups in the domain '.254.169.in-addr.arpa' should also be resolved
      # using mDNS.
      #
      # TODO - those are the IPs auto-allocated with ZeroConf. In my (common)
      # situation, I have a net of OS X machines behind and ADSL firewall box,
      # and all IPs were allocated in 192.168.123.*. I can do mDNS queries to
      # get these addrs, but I can't do an mDNS query to reverse lookup the
      # addrs. There are security reasons to not allow all addrs to be reversed
      # on the local network, but maybe it wouldn't be so bad if MDNS was after
      # DNS, so it only did it for addrs that were unmatched by DNS?
      #
      # If the search domains includes .local, we can add .local to it only if
      # it has no dots and wasn't absolute.
      #
      # TODO - I don't know, if ndots is zero, should local -> local.local? Should we
      # respect ndots? I don't want to get bogged down in this now.
      candidates = nil
      name = DNS::Name.create(name)
      if name.absolute?
        candidates = [name]
      else
        if @config.ndots <= name.length - 1
          candidates = [DNS::Name.new(name.to_a)]
        else
          candidates = []
        end
        # mDNS MUST NOT append a search suffix to a domain name with 2 or more labels.
        unless name.length > 1
          candidates.concat(@config.search.map {|domain| DNS::Name.new(name.to_a + domain)})
        end
      end
      return candidates.select { |n| n <= 'local' || n <= '254.169.in-addr.arpa' } .uniq
    end

    DefaultTimeout = 5

    def each_resource(name, typeclass, &proc)
      lazy_initialize
      q = Queue.new
      senders = {}

      begin
        generate_candidates(name).each do |candidate|
          msg = DNS::Message.new
          # RD is false in mDNS
          msg.rd = 0
          msg.add_question(candidate, typeclass)
          unless sender = senders[candidate]
            sender = senders[candidate] =
              @requester.sender(msg, candidate, q)
          end

          sender.send
          # TODO - resend the msg, in case it got lost? Don't know if UDP
          # really can get lost on a local network.

          # We want all the answers we can get, within the timeout period.
          # TODO - we will ask the question for the next candidate, even if the
          # first candidate returned answers. Don't do that!
          begin
            timeout(DefaultTimeout) do
              loop do
                reply = reply_name = nil
                reply, reply_name = q.pop
                case reply.rcode
                  when DNS::RCode::NoError
                    extract_resources(reply, reply_name, typeclass, &proc)
                  when DNS::RCode::NXDomain
                    raise DNS::Config::NXDomain.new(reply_name)
                  else
                    # TODO - check why this
                    raise DNS::Config::OtherResolvError.new(reply_name)
                end
              end
            end
          rescue TimeoutError
          end
        end
      ensure
        @requester.delete(q)
      end
    end

    # TODO - I really need to pull this code from Resolv:DNS, not have a copy.
    def extract_resources(msg, name, typeclass)
      if typeclass < DNS::Resource::ANY
        n0 = DNS::Name.create(name)
        msg.each_answer {|n, ttl, data|
          yield data if n0 == n
        }
      end
      yielded = false
      n0 = DNS::Name.create(name)
      msg.each_answer {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
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
                  yield data
          end
        end
      }
    end

      # TODO - maybe I should allow the port to be configurable, so mDNS can run
      # on other ports? Add back in later, as needed.
      class MulticastUDP < DNS::Requester
        def initialize
          super()
          @sock = UDPSocket.new
          @sock.fcntl(Fcntl::F_SETFD, 1)
          # TODO - why can't Message ensure it's ID's are unique?
          @id = {}
          @id.default = -1
          @thread = Thread.new {
            loop {
              reply, from = @sock.recvfrom(UDPSize)
              #STDERR.print("recv local=#{@sock.addr.inspect} < peer=#{from} len=#{reply.length}\n")
              msg = begin
                DNS::Message.decode(reply)
              rescue DecodeError
                STDERR.print("DNS message decoding error: #{reply.inspect}\n")
                next
              end
              if s = @senders[msg.id]
                s.recv msg
              else
                #STDERR.print("non-handled DNS message: #{msg.inspect} from #{from.inspect}\n")
              end
            }
          }
        end

        def sender(msg, data, queue, port=Port)
          # TODO - clean up ID handling later
          service = Addr
          id = Thread.exclusive {
            @id[service] = (@id[service] + 1) & 0xffff
          }
          # TODO - Message.encode should take a msg ID argument.
          request = msg.encode
          request[0,2] = [id].pack('n')
          return @senders[id] =
            Sender.new(request, data, @sock, Addr, port, queue)
        end

        class Sender < DNS::Requester::Sender
          def initialize(msg, data, sock, host, port, queue)
            super(msg, data, sock, queue)
            @host = host
            @port = port

            # ruby 1.6 code;
#           super(data, queue)
#           @msg = msg
#           @sock = sock
#           @host = host
#           @port = port
          end

          def send
            #STDERR.print("send query for #{@data} to #{@host}:#{@port}\n")
            @sock.send(@msg, 0, @host, @port)
          end
        end
      end

  end
end

class Resolv
  # This is a bit of hack, but I want MDNS to be after Hosts, but it can't be
  # at the end because DNS throws an error if it fails a lookup.  This is fixed
  # in the latest CVS, but for now we need to be before DNS.
  DefaultResolver.resolvers.insert(-2, Resolv::MDNS.new)
end

