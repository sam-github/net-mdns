=begin
  Copyright (C) 2005 Sam Roberts

  This library is free software; you can redistribute it and/or modify it
  under the same terms as the ruby language itself, see the file COPYING for
  details.
=end

require 'net/dns/v2mdns.rb'

module Net
  module DNS
    module DNSSD

      # DNS-SD names look like;
      #  [<instance>.]<_service>.<_protocol>.<domain>
      # for example:
      #   _http._tcp.local
      #   guest._http._tcp.local
      #   Ensemble Musique._daap._tcp.local
      # The <_service>.<_protocol> combined is the <type>.
      #
      # Return either:
      #  [ <domain>, <type> ]
      # or
      #  [ <domain>, <type>, <instance>]
      def self.name_parse(dnsname)
        domain, t1, t0, name = dnsname.to_a.reverse.map {|n| n.to_s}
        [ domain, t0 + '.' + t1, name].compact
      end

      # TODO - derive both from a common Reply
      class BrowseReply
        attr_reader :interface, :name, :type, :domain, :fullname
        def initialize(an)
          @interface = nil
          @fullname = ansrv.name.to_s
          @domain, @type, @name = DNSSD.name_parse(an.data.name)
        end
      end

      def self.browse(type, domain = '.local', *ignored)
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

      class ResolveReply
        attr_reader :interface, :name, :type, :domain, :fullname, :target, :port, :priority, :weight, :text_record
        def initialize(ansrv, antxt)
          @interface = nil
          @fullname = ansrv.name.to_s
          @domain, @type, @name = DNSSD.name_parse(ansrv.name)
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

      def self.resolve(name, type, domain = '.local', *ignored)
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

      class RegisterReply
        attr_reader :name, :type, :domain
        def initialize(name, type, domain)
          @name, @type, @domain = name, type, domain
        end
      end

      def self.register(name, type, domain, port, txt, *ignored)
        dnsname = DNS::Name.create(name)
        dnsname << DNS::Name.create(type)
        dnsname << DNS::Name.create(domain)
        dnsname.absolute = true

        s = MDNS::Service.new(name, type, port, txt) do |s|
          s.domain = domain
        end

        yield RegisterReply.new(name, type, domain)

        s
      end

    end
  end
end

