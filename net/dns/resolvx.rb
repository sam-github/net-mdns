# Extensions to the Resolv module, as opposed to modications.

require 'net/dns/resolv'

class Resolv
  class DNS

    class Message

      # Is message a query?
      def query?
        qr == 0
      end

      # Is message a response?
      def response?
        !query?
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
      def <<(arg)
        arg = Name.create(arg)
        @labels << arg.to_a
        @absolute = arg.absolute?
      end

      def +(arg)
        arg = Name.create(arg)
        Name.new(@labels + arg.to_a, arg.absolute?)
      end

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

