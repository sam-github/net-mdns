# $Id: $

require 'resolv'

unless Resolv::DNS::Resource::IN.constants.include? 'SRV'

  class Resolv
    class DNS
      class Resource
        module IN


          # NOTE - This is in ruby 1.8's lib now, but unless you use CVS you won't see it, so
          # I include a copy here, as well.
          #
          # SRV resource record defined in RFC 2782
          # 
          # These records identify the hostname and port that a service is
          # available at.
          # 
          # The format is:
          #   _Service._Proto.Name TTL Class SRV Priority Weight Port Target
          #
          # The fields specific to SRV are defined in RFC 2782 as meaning:
          # - +priority+ The priority of this target host.  A client MUST attempt
          #   to contact the target host with the lowest-numbered priority it can
          #   reach; target hosts with the same priority SHOULD be tried in an
          #   order defined by the weight field.  The range is 0-65535.  Note that
          #   it is not widely implemented and should be set to zero.
          # 
          # - +weight+ A server selection mechanism.  The weight field specifies
          #   a relative weight for entries with the same priority. Larger weights
          #   SHOULD be given a proportionately higher probability of being
          #   selected. The range of this number is 0-65535.  Domain administrators
          #   SHOULD use Weight 0 when there isn't any server selection to do, to
          #   make the RR easier to read for humans (less noisy). Note that it is
          #   not widely implemented and should be set to zero.
          #
          # - +port+  The port on this target host of this service.  The range is 0-
          #   65535.
          # 
          # - +target+ The domain name of the target host. A target of "." means
          #   that the service is decidedly not available at this domain.
          class SRV < Resource
            ClassHash[[TypeValue = 33, ClassValue = ClassValue]] = self

            # Create a SRV resource record.
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

            # Do I want this?
            def inspect
              "IN::SRV priority=#{priority} weight=#{weight} target=#{target}:#{port}"
            end
          end


        end
      end
    end
  end

end

class Resolv

  # The default resolvers.
  def self.default_resolvers
    DefaultResolver.resolvers
  end

  # The resolvers configured.
  attr_reader :resolvers

  class DNS
    class Config
      attr_reader :ndots
      attr_reader :search
    end

    class Name
      def inspect
        n = to_s
        n << '.' if absolute?
        return n
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

