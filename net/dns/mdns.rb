=begin
  Copyright (C) 2005 Sam Roberts

  This library is free software; you can redistribute it and/or modify it
  under the same terms as the ruby language itself, see the file COPYING for
  details.
=end

require 'resolv'
require 'net/dns/resolvx'

class Resolv
  #:main:Resolv::MDNS
  #:title:mDNS - multicast DNS and service discovery (aka "Rendezvous")
  #
  # Author::     Sam Roberts <sroberts@uniserve.com>
  # Copyright::  Copyright (C) 2005 Sam Roberts
  # License::    May be distributed under the same terms as Ruby
  # Version::    0.1
  # Homepage::   http://vpim.rubyforge.org/mdns
  #
  # == Summary
  # An extension to the standard 'resolv' resolver library that adds support
  # for multicast DNS.  mDNS is an extension of hierarchical, unicast DNS to
  # link-local unicast. It is most widely known because it is part of Apple's
  # OS X "Rendezvous" system, where it is used to do service discovery over
  # local networks.
  #
  # MDNS can be used for:
  # - name to address lookups on local networks
  # - address to name lookups on local networks (only for link-local addresses)
  # - discovery of services on local networks
  #
  # = Example
  #   require 'net/http'
  #   require 'net/dns/mdns-resolv'
  #   require 'resolv-replace'
  #   
  #   # Address lookup
  #   
  #   begin
  #   puts Resolv.getaddress('example.local')
  #   rescue Resolv::ResolvError
  #     puts "no such address!"
  #   end
  #   
  #   # Service discovery
  #   
  #   mdns = Resolv::MDNS.new
  #   
  #   mdns.each_resource('_http._tcp.local', Resolv::DNS::Resource::IN::PTR) do |rrhttp|
  #     service = rrhttp.name
  #     host = nil
  #     port = nil
  #     path = '/'
  #   
  #     rrsrv = mdns.getresource(rrhttp.name, Resolv::DNS::Resource::IN::SRV)
  #     host, port = rrsrv.target.to_s, rrsrv.port
  #     rrtxt = mdns.getresource(rrhttp.name, Resolv::DNS::Resource::IN::TXT)
  #     if  rrtxt.data =~ /path=(.*)/
  #       path = $1
  #     end
  #   
  #     http = Net::HTTP.new(host, port)
  #   
  #     headers = http.head(path)
  #   
  #     puts "#{service[0]} on #{host}:#{port}#{path} was last-modified #{headers['last-modified']}"
  #   end
  #   
  # == Address Lookups
  #
  # When used for name lookups, it is most useful to add MDNS to the default
  # set of resolvers queried when using the 'resolv' module methods. This is
  # done by doing:
  #   require 'net/dns/mdns-resolv'
  #   Resolv.getaddress('localhost') # resolved using Resolv::Hosts("/etc/hosts")
  #   Resolv.getaddress('www.example.com') # resolved using Resolv::DNS
  #   Resolv.getaddress('example.local') # resolved using Resolv::MDNS
  # Using this approach means that both global DNS names and local names can be
  # resolved.  When doing this, you may also consider doing:
  #   require 'resolv-replace'
  # This has the effect of replacing the default ruby implementation of address
  # lookup in IPSocket, TCPSocket, UDPSocket, and SOCKSocket with
  # Resolv.getaddress, so (if 'net/dns/mdns-resolv' has been required) the
  # standard libraries TCP/IP classes will use mDNS for name lookups in the .local domain.
  #
  # == Service Discovery
  #
  # Service discovery consists of 2 stages:
  # - enumerating the names of the instances of the service
  # - resolving the instance names
  #
  # = Service Enumeration
  #
  # To do this query the pointer records (Resolv::DNS::Resource::IN::PTR) for
  # names of the form _svc._prot.local. The values of svc and prot for common
  # services can be found at http://www.dns-sd.org/ServiceTypes.html.
  # The first label of the name returned is suitable for display to peoplem, and
  # should be unique in the network.
  #
  # = Service Resolution
  #
  # In order to resolve a service name query the service record
  # (Resolv::DNS::Resource::IN::SRV) for the name. The service record contains
  # a host and port to connect to. The host name will have to be resolved to
  # an address. This can be done explicitly using mDNS or, if resolv-replace
  # and mdns-default have been required, it will be done by the standard library.
  # In addition, some services put "extra" information about the service in a
  # text (Resolv::DNS::Resource::IN::TXT) record associated with the service name.
  # The format of the text record is service-specific.
  #
  # == For More Information
  #
  # See the following:
  # - draft-cheshire-dnsext-multicastdns-04.txt for a description of mDNS
  # - RFC 2782 for a description of DNS SRV records
  # - draft-cheshire-dnsext-dns-sd-02.txt for a description of how to
  #   use SRV, PTR, and TXT records for service discovery
  # - http://www.dns-sd.org
  #
  # == Comparison to the DNS-SD Extension
  #
  # The DNS-SD project at http://dnssd.rubyforge.org/wiki/wiki.pl is another
  # approach to mDNS and service discovery.
  #
  # DNS-SD is a compiled ruby extension implemented on top of the dns_sd.h APIs
  # published by Apple. These APIs work by contacting a local mDNS daemon
  # (through unix domain sockets), and as such will be more efficient (they can
  # take advantage of the daemon's cache), and likely a better way of doing
  # mDNS queries than using pure ruby. Also, the mDNS daemon is capable of
  # advertising services over the network.
  #
  # Currently, the only thing I'm aware of Resolv::MDNS doing that DNSSD
  # doesn't is integrate into the standard library so that link-local domain
  # names can be used throughout the standard networking classes.  There is no
  # reason it can't do this, and I'll try and add that capability as soon as I
  # find a way to install and use DNS-SD, which leads to why you might be
  # interested in Resolv::MDNS.
  #
  # However, the DNS-SD extension requires the dns_sd.h APIs, and installing
  # the Apple responder can be quite difficult, and requires a running daemon.
  # It also requires compiling the extension. If this turns out to be difficult
  # for you, as it has for me, Resolv::MDNS may be useful to you.
  #
  # == Samples
  # 
  # There are a few samples in the samples/ directory:
  # - mdns.rb is useful for finding out as much as possible about services on .local
  # - mdns_demo.rb is a sample provided by Ben Giddings, with better docs, showing
  #   the call sequence he uses when resolving services. Thanks, Ben!
  # 
  # == TODO
  #
  # - Implement a Resolv:: object that uses the DNS-SD project, so the standard
  #   library will use it for .local name lookups.
  # - Implement response cacheing and service advertising in Resolv::MDNS.
  # - Implement a higher level service discovery API that will work with either
  #   DNS-SD or Resolv::MDNS, so either can be used (as available) without code
  #   changes.
  # - Various API improvements, testing, ...
  #
  # == Author
  # 
  # Any feedback, questions, problems, etc., please contact me, Sam Roberts,
  # via dnssd-developers@rubyforge.org, or directly.
  class MDNS
    # link-local multicast address
    Addr = "224.0.0.251"
    Port = 5353
    UDPSize = 9000
    DefaultTimeout = 3


    # See Resolv::DNS#new.
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

    attr_reader :requestor # :nodoc:

    # See Resolv::DNS#getaddress.
    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    # See Resolv::DNS#getaddresss.
    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    # See Resolv::DNS#each_address.
    def each_address(name)
      each_resource(name, DNS::Resource::IN::A) {|resource| yield resource.address}
    end

    # See Resolv::DNS#getname.
    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("DNS result has no information for #{address}")
    end

    # See Resolv::DNS#getnames.
    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    # See Resolv::DNS#each_name.
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

    # See Resolv::DNS#getresource.
    def getresource(name, typeclass)
      each_resource(name, typeclass) {|resource| return resource}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    # See Resolv::DNS#getresources.
    def getresources(name, typeclass)
      ret = []
      each_resource(name, typeclass) {|resource| ret << resource}
      return ret
    end

    def generate_candidates(name) # :nodoc:
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

    # See Resolv::DNS#eachresource.
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

          # We want all the answers we can get, within the timeout period.
          # TODO - we will ask the question for the next candidate, even if the
          # first candidate returned answers. Don't do that!
          begin
#puts "timeout=#{DefaultTimeout}"
            timeout(DefaultTimeout) do
              loop do
#pp sender
                reply = reply_name = nil
                reply, reply_name = q.pop
#pp reply
#pp reply_name
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
    def extract_resources(msg, name, typeclass) # :nodoc:
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

    class MulticastUDP < DNS::Requester # :nodoc:
      def initialize
        super()
        @sock = UDPSocket.new
        @sock.fcntl(Fcntl::F_SETFD, 1)
#       @sock.bind(Addr, Port) # doesn't work if a mDNS daemon is running
        # TODO - why can't Message ensure it's ID's are unique?
        @id = {}
        @id.default = -1
        @thread = Thread.new do
          loop do
            reply, from = @sock.recvfrom(UDPSize)
            #STDERR.print("recv local=#{@sock.addr.inspect} < peer=#{from} len=#{reply.length}\n")
            msg =
              begin
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
          end
        end
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

