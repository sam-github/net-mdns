# Extensions to the standard library's Resolv module. Some have been accepted,
# some have not been submitted, and some haven't been accepted (doomed to live
# out their life far from the core...).
#
# The extensions that have been accepted are conditionally defined because they
# have already been accepted into ruby 1.8's cvs, and will show up RSN in a release.

require 'resolv'

class Resolv
  class DNS

    class Message

      def query?
        qr == 0
      end

      def response?
        qr == 1
      end

      def extract_resources(name, typeclass)
        msg = self
        if typeclass < DNS::Resource::ANY
          n0 = DNS::Name.create(name)
          msg.each_answer {|n, ttl, data|
            yield n, ttl, data if n0 == n
          }
          # FIXME - should return here
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
              # FIXME - Would this be a good place for a 'restart'?
            end
          end
        }
        # FIXME - by returning here, you miss records with the CNAME.
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
      attr_reader :nameservers
    end

    #
    # DNS names are hierarchical in a similar sense to ruby classes/modules, and the
    # comparison operators are defined similarly to those of Module. A name is
    # +<+ another if it is a subdomain.
    #   www.example.com < example.com # -> true
    #   example.com < example.com # -> false
    #   example.com <= example.com # -> true
    #   com < example.com # -> false
    #   bar.com < example.com # -> nil
    #
    # Note that #== does not consider two names equal if they differ in whether
    # they are #absolute?, but #equal? considers only the label when comparing
    # names.
    class Name
      def equal?(name)
        n = Name.create(name)

        @labels == n.to_a
      end

      def related?(name)
        n = Name.create(name)

        l = length < n.length ? length : n.length

        @labels[-l, l] == n.to_a[-l, l]
      end

      def lt?(name)
        n = Name.create(name)
        length > n.length && to_a[-n.length, n.length] == n.to_a
      end


      # Summary:
      #   name < other   =>  true, false, or nil
      # 
      # Returns true if +name+ is a subdomain of +other+. Returns 
      # <code>nil</code> if there's no relationship between the two. 
      def <(name)
        n = Name.create(name)

        return nil unless self.related?(n)

        lt?(n)
      end

      # Summary:
      #   name > other   =>  true, false, or nil
      # 
      # Same as +other < name+, see #<.
      def >(name)
        n = Name.create(name)

        n < self
      end

      # Summary:
      #   name <= other   =>  true, false, or nil
      # 
      # Returns true if +name+ is a subdomain of +other+ or is the same as
      # +other+. Returns <code>nil</code> if there's no relationship between
      # the two. 
      def <=(name)
        n = Name.create(name)
        self.equal?(n) || self < n
      end

      # Summary:
      #   name >= other   =>  true, false, or nil
      # 
      # Returns true if +name+ is an ancestor of +other+, or the two DNS names
      # are the same. Returns <code>nil</code> if there's no relationship
      # between the two. 
      def >=(name)
        n = Name.create(name)
        self.equal?(n) || self > n
      end

      # Summary:
      #     name <=> other   => -1, 0, +1, nil
      #  
      # Returns -1 if +name+ is a subdomain of +other+, 0 if
      # +name+ is the same as +other+, and +1 if +other+ is a subdomain of
      # +name+, or nil if +name+ has no relationship with +other+.
      def <=>(name)
        n = Name.create(name)

        return nil unless self.related?(n)

        return -1 if self.lt?(n)
        return +1 if n.lt?(self)
        # must be #equal?
        return  0
      end

    end
  end
end

=begin
class Resolv
  class DNS
    class Resource
      module IN

        class SRV
          def inspect
            "IN::SRV priority=#{priority} weight=#{weight} target=#{target}:#{port}"
          end
        end

        class TXT
          def inspect
            "IN::TXT data=#{strings.inspect}"
          end
        end

        class PTR
          def inspect
            "IN::PTR name=#{name}"
          end
        end

      end
    end
  end
end

=end

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

          end


        end
      end
    end
  end

end

