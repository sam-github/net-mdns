=begin
  Copyright (C) 2005 Sam Roberts

  This library is free software; you can redistribute it and/or modify it
  under the same terms as the ruby language itself, see the file COPYING for
  details.
=end

require 'net/dns/v2mdns.rb'

module Net
  module DNS

    # = DNS-SD over mDNS
    #
    # An implementation of DNS-SD using Net::DNS::MDNS.
    #
    # DNS-SD is described in draft-cheshire-dnsext-dns-sd.txt, see
    # http://www.dns-sd.org for more information. It is most often seen as part
    # of Apple's OS X, but is widely useful.
    #
    # These APIs accept and return a set of arguments which are documented once,
    # here, for convenience.
    #
    # - type: DNSSD classifies services into types using a naming convention.
    #   That convention is <_service>.<_protocol>.  The underscores ("_") serve
    #   to differentiate from normal DNS names. Protocol is always one of
    #   "_tcp" or "_udp". The service is a short name, see the list at
    #   http://www.dns-sd.org/ServiceTypes.html. A common service is "http", the type
    #   of which would be "_http._tcp".
    #
    # - domain: Services operate in a domain, theoretically. In current practice,
    #   that domain is always "local".
    #
    # - name: Service lookup with #browse results in a name of a service of that
    #   type. That name is associated with a target (a host name), port,
    #   priority, and weight, as well as series of key to value mappings,
    #   specific to the service. In practice, priority and weight are widely
    #   ignored.
    #
    # - fullname: The concatention of the service name (optionally), type, and
    #   domain results in a single dot-seperated domain name - the "fullname".
    #   It could be decoded with #z_name_parse, but that won't generally be
    #   necessary.
    #
    # Services are advertised and resolved over specific network interfaces.
    # Currently, Net::DNS::MDNS supports only a single default interface, and
    # the interface will always be +nil+.
    module MDNSSD

      # A reply yielded by #browse, see MDNSSD for a description of the attributes.
      class BrowseReply
        attr_reader :interface, :fullname, :name, :type, :domain
        def initialize(an) # :nodoc:
          @interface = nil
          @fullname = an.name.to_s
          @domain, @type, @name = DNSSD.z_name_parse(an.data.name)
        end
      end

      # Lookup a service by +type+ and +domain+.
      #
      # Yields a BrowseReply as services are found, in a background thread, not
      # the caller's thread!
      #
      # Returns a MDNS::BackgroundQuery, call MDNS::BackgroundQuery#stop when
      # you have found all the replies you are interested in.
      def self.browse(type, domain = '.local', *ignored) # :yield: BrowseReply
        dnsname = DNS::Name.create(type)
        dnsname << DNS::Name.create(domain)
        dnsname.absolute = true

        q = MDNS::BackgroundQuery.new(dnsname, IN::PTR) do |q, answers|
          answers.each do |an|
            yield BrowseReply.new( an )
          end
        end
        q
      end

      # A reply yielded by #resolve, see MDNSSD for a description of the attributes.
      class ResolveReply
        attr_reader :interface, :fullname, :name, :type, :domain, :target, :port, :priority, :weight, :text_record
        def initialize(ansrv, antxt) # :nodoc:
          @interface = nil
          @fullname = ansrv.name.to_s
          @domain, @type, @name = DNSSD.z_name_parse(ansrv.name)
          @target = ansrv.data.target
          @port = ansrv.data.port
          @priority = ansrv.data.priority
          @weight = ansrv.data.weight

          @text_record = {}
          antxt.data.strings.each do |kv|
            kv.match(/([^=]+)=([^=]+)/)
            @text_record[$1] = $2
          end
        end
      end

      # Resolve a service instance by +name+, +type+ and +domain+.
      #
      # Yields a ResolveReply as service instances are found, in a background
      # thread, not the caller's thread!
      #
      # Returns a MDNS::BackgroundQuery, call MDNS::BackgroundQuery#stop when
      # you have found all the replies you are interested in.
      def self.resolve(name, type, domain = '.local', *ignored) # :yield: ResolveReply
        dnsname = DNS::Name.create(name)
        dnsname << DNS::Name.create(type)
        dnsname << DNS::Name.create(domain)
        dnsname.absolute = true

        # This may look a bit painful, but we can't report an instance of a
        # service until we have both a SRV and a TXT resource record for it.

        rrs = Hash.new { |h,k| h[k] = Hash.new }

        q = MDNS::BackgroundQuery.new(dnsname, IN::ANY) do |q, answers|
          answers.each do |an|
            rrs[an.name][an.type] = an

            ansrv, antxt = rrs[an.name][IN::SRV], rrs[an.name][IN::TXT]

            if ansrv && antxt
              rrs.delete an.name
              yield ResolveReply.new( ansrv, antxt )
            end
          end
        end
        q
      end

      # A reply yielded by #register, see MDNSSD for a description of the attributes.
      class RegisterReply
        attr_reader :interface, :fullname, :name, :type, :domain
        def initialize(name, type, domain)
          @interface = nil
          @fullname = (DNS::Name.create(name) << type << domain).to_s
          @name, @type, @domain = name, type, domain
        end
      end

      # Register a service instance on the local host.
      #
      # +txt+ is a Hash of String keys to String values.
      #
      # Because the service +name+ may already be in use on the network, a
      # different name may be registered than that requested. Because of this,
      # if a block is supplied, a RegisterReply will be yielded so that the
      # actual service name registered may be seen.
      #
      # Returns a MDNS::Service, call MDNS::Service#stop when you no longer
      # want to advertise the service.
      #
      # NOTE - The service +name+ should be unique on the network, MDNSSD
      # doesn't currently attempt to ensure this. This will be fixed in
      # an upcoming release.
      def self.register(name, type, domain, port, txt = {}, *ignored) # :yields: RegisterReply
        dnsname = DNS::Name.create(name)
        dnsname << DNS::Name.create(type)
        dnsname << DNS::Name.create(domain)
        dnsname.absolute = true

        s = MDNS::Service.new(name, type, port, txt) do |s|
          s.domain = domain
        end

        yield RegisterReply.new(name, type, domain) if block_given?

        s
      end

      # Decode a DNS-SD domain name. The format is:
      #   [<instance>.]<_service>.<_protocol>.<domain>
      #
      # Examples are:
      #   _http._tcp.local
      #   guest._http._tcp.local
      #   Ensemble Musique._daap._tcp.local
      #
      # The <_service>.<_protocol> combined is the <type>.
      #
      # Return either:
      #  [ <domain>, <type> ]
      # or
      #  [ <domain>, <type>, <instance>]
      #
      # Because of the order of the return values, it can be called like:
      #   domain, type = MDNSSD.z_name_parse(fullname)
      # or
      #   domain, type, name = MDNSSD.z_name_parse(fullname)
      # If there is no name component to fullname, name will be nil.
      def self.z_name_parse(dnsname)
        domain, t1, t0, name = dnsname.to_a.reverse.map {|n| n.to_s}
        [ domain, t0 + '.' + t1, name].compact
      end


    end
  end
end

