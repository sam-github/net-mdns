require 'resolv'

class Resolv
  class MDNS
    # draft-chesire-dnsex-multicastdns-01.txt
    #
    # Extends "normal" DNS to link-local multicast.
    #
    # STD0013 (RFC 1035, etc.)
    # ftp://ftp.isi.edu/in-notes/iana/assignments/dns-parameters

    Addr = "224.0.0.251"
    Port = 5353
    UDPSize = 512

    def initialize(config="/etc/resolv.conf")
      @mutex = Mutex.new
      @config = Config.new(config)
      @initialized = nil
    end

    def lazy_initialize
      @mutex.synchronize {
        unless @initialized
        @config.lazy_initialize

        @requester = Requester::MulticastUDP.new

        @initialized = true
        end
      }
    end

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
      each_resource(name, Resource::IN::A) {|resource| yield resource.address}
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
      when Name
        ptr = address
      when IPv4::Regex
        ptr = IPv4.create(address).to_name
      when IPv6::Regex
        ptr = IPv6.create(address).to_name
      else
        raise ResolvError.new("cannot interpret as address: #{address}")
      end
        each_resource(ptr, Resource::IN::PTR) {|resource| yield resource.name}
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

    def each_resource(name, typeclass, &proc)
      lazy_initialize
      q = Queue.new
      senders = {}
      begin
        @config.resolv(name) {|candidate, tout|
          # TODO Message needs to ensure it's message IDs are unique...
          msg = Message.new
          msg.rd = 0
          msg.add_question(candidate, typeclass)
          unless sender = senders[candidate]
            sender = senders[nameserver] =
              @requester.sender(msg, candidate, q)
          end
          sender.send
          reply = reply_name = nil
          timeout(tout) { reply, reply_name = q.pop }
          case reply.rcode
          when RCode::NoError
            extract_resources(reply, reply_name, typeclass, &proc)
            return
          when RCode::NXDomain
            raise Config::NXDomain.new(reply_name)
          else
            raise Config::OtherResolvError.new(reply_name)
          end
        }
      ensure
        @requester.delete(q)
      end
    end

    def extract_resources(msg, name, typeclass)
      if typeclass < Resource::ANY
        n0 = Name.create(name)
        msg.each_answer {|n, ttl, data|
          yield data if n0 == n
        }
      end
      yielded = false
      n0 = Name.create(name)
      msg.each_answer {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
            yielded = true
          when Resource::CNAME
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

    class Requester
      def initialize
        @senders = {}
      end

      def delete(arg)
        case arg
        when Sender
          @senders.delete_if {|k, s| s == arg }
        when Queue
          @senders.delete_if {|k, s| s.queue == arg }
        else
          raise ArgumentError.new("neither Sender or Queue: #{arg}")
        end
      end

      class Sender
        def initialize(data, queue)
          @data = data
          @queue = queue
        end
        attr_reader :queue

        def recv(msg)
          @queue.push([msg, @data])
        end
      end

      class MulticastUDP < Requester
        def initialize
          super()
          @sock = UDPSocket.new
          # Set close-on-exec.
          @sock.fcntl(Fcntl::F_SETFD, 1)
          @thread = Thread.new {
            loop {
              reply, from = @sock.recvfrom(UDPSize)
              STDERR.print("recv local=#{@sock.addr.inspect} < peer=#{from}")
              msg = begin
                      Message.decode(reply)
                    rescue DecodeError
                      STDERR.print("DNS message decoding error: #{reply.inspect}\n")
                      next
                    end
              if s = @senders[[[from[3],from[1]],msg.id]]
                s.recv msg
              else
                #STDERR.print("non-handled DNS message: #{msg.inspect} from #{from.inspect}\n")
              end
            }
          }
        end

        def sender(msg, data, queue, port=Port)
          service = [host, port]
          request = msg.encode

          return @senders[id] =
            Sender.new(request, data, @sock, host, port, queue)
        end

        class Sender < Requester::Sender
          def initialize(msg, data, sock, host, port, queue)
            super(data, queue)
            @msg = msg
            @sock = sock
            @host = host
            @port = port
          end

          def send
            @sock.send(@msg, 0, @host, @port)
          end
        end
      end
    end

    class Config
      def initialize(filename="/etc/resolv.conf")
        @mutex = Mutex.new
        @filename = filename
        @initialized = nil
      end

      def lazy_initialize
        @mutex.synchronize {
          unless @initialized
          @nameserver = []
          @search = nil
          @ndots = 1
          begin
            open(@filename) {|f|
              f.each {|line|
                line.sub!(/[#;].*/, '')
                keyword, *args = line.split(/\s+/)
                next unless keyword
                case keyword
                when 'nameserver'
                  @nameserver += args
                when 'domain'
                  if args[0]
                    @search = [args[0]]
                  end
                when 'search'
                  @search = args
                end
              }
            }
          rescue Errno::ENOENT
          end

          @nameserver = ['0.0.0.0'] if @nameserver.empty?
          unless @search
            hostname = Socket.gethostname
            if /\./ =~ hostname
              @search = [$']
            else
              @search = ['']
            end
          end
          @initialized = true
          end
        }
      end

      def single?
        lazy_initialize
        if @nameserver.length == 1
          return @nameserver[0]
        else
          return nil
        end
      end

      def generate_candidates(name)
        candidates = nil
        name = name.to_s if Name === name
        if /\.\z/ =~ name
          candidates = [name]
        elsif @ndots <= name.tr('^.', '').length
          candidates = [name, *@search.collect {|domain| name + '.' + domain}]
        else
          candidates = [*@search.collect {|domain| name + '.' + domain}]
        end
        candidates.collect! {|c|
          c = c.dup
          c.gsub!(/\.\.+/, '.')
          c.chomp!('.')
          c
        }
        return candidates
      end

      InitialTimeout = 5

      def generate_timeouts
        ts = [InitialTimeout]
        ts << ts[-1] * 2 / @nameserver.length
        ts << ts[-1] * 2
        ts << ts[-1] * 2
        return ts
      end

      # MOD: only resolve names in the .local and 254.169.in-addr.arpa domains
      # MOD: don't use the nameserver addresses
      def resolv(name)
        candidates = generate_candidates(name)
        timeouts = generate_timeouts
        begin
          candidates.each {|candidate|
            STDERR.puts "candidate: #{candidate}"
              next unless candidate =~ /\.local\.?$/ || candidate =~ /\.254\.169\.in-addr\.arpa\.?$/
              begin
                timeouts.each {|tout|
                  begin
                    yield candidate, tout
                  rescue TimeoutError
                  end
                }
                raise ResolvError.new("DNS resolv timeout: #{name}")
              rescue NXDomain
              end
            }
        rescue OtherResolvError
          raise ResolvError.new("DNS error: #{$!.message}")
        end
          raise ResolvError.new("DNS resolv error: #{name}")
      end

      class NXDomain < ResolvError
      end

      class OtherResolvError < ResolvError
      end
    end

    module OpCode
      Query = 0
      IQuery = 1
      Status = 2
      Notify = 4
      Update = 5
    end

    module RCode
      NoError = 0
      FormErr = 1
      ServFail = 2
      NXDomain = 3
      NotImp = 4
      Refused = 5
      YXDomain = 6
      YXRRSet = 7
      NXRRSet = 8
      NotAuth = 9
      NotZone = 10
      BADVERS = 16
      BADSIG = 16
      BADKEY = 17
      BADTIME = 18
      BADMODE = 19
      BADNAME = 20
      BADALG = 21
    end

    class DecodeError < StandardError
    end

    class EncodeError < StandardError
    end

    module Label
      def self.split(arg)
        labels = []
        arg.scan(/[^\.]+/) {labels << Str.new($&)}
        return labels
      end

      class Str
        def initialize(string)
          @string = string
          @downcase = string.downcase
        end
        attr_reader :string, :downcase

        def to_s
          return @string
        end

        def inspect
          return "#<#{self.class} #{self.to_s}>"
        end

        def ==(other)
          return @downcase == other.downcase
        end

        def eql?(other)
          return self == other
        end

        def hash
          return @downcase.hash
        end
      end
    end

    class Name
      def self.create(arg)
        case arg
        when Name
          return arg
        when String
          return Name.new(Label.split(arg))
        else
          raise ArgumentError.new("cannot interprete as DNS name: #{arg.inspect}")
        end
      end

      def initialize(labels)
        @labels = labels
      end

      def ==(other)
        return @labels == other.to_a
      end

      def eql?(other)
        return self == other
      end

      def hash
        return @labels.hash
      end

      def to_a
        return @labels
      end

      def length
        return @labels.length
      end

      def [](i)
        return @labels[i]
      end

      def to_s
        return @labels.join('.')
      end
    end

    class Message
      @@identifier = -1

      def initialize(id = (@@identifier += 1) & 0xffff)
        @id = id
        @qr = 0
        @opcode = 0
        @aa = 0
        @tc = 0
        @rd = 0 # recursion desired
        @ra = 0 # recursion available
        @rcode = 0
        @question = []
        @answer = []
        @authority = []
        @additional = []
      end

      attr_accessor :id, :qr, :opcode, :aa, :tc, :rd, :ra, :rcode
      attr_reader :question, :answer, :authority, :additional

      def ==(other)
        return @id == other.id &&
          @qr == other.qr &&
          @opcode == other.opcode &&
          @aa == other.aa &&
          @tc == other.tc &&
          @rd == other.rd &&
          @ra == other.ra &&
          @rcode == other.rcode &&
          @question == other.question &&
          @answer == other.answer &&
          @authority == other.authority &&
          @additional == other.additional
      end

      def add_question(name, typeclass)
        @question << [Name.create(name), typeclass]
      end

      def each_question
        @question.each {|name, typeclass|
          yield name, typeclass
        }
      end

      def add_answer(name, ttl, data)
        @answer << [Name.create(name), ttl, data]
      end

      def each_answer
        @answer.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_authority(name, ttl, data)
        @authority << [Name.create(name), ttl, data]
      end

      def each_authority
        @authority.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_additional(name, ttl, data)
        @additional << [Name.create(name), ttl, data]
      end

      def each_additional
        @additional.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def each_resource
        each_answer {|name, ttl, data| yield name, ttl, data}
        each_authority {|name, ttl, data| yield name, ttl, data}
        each_additional {|name, ttl, data| yield name, ttl, data}
      end

      def encode
        return MessageEncoder.new {|msg|
          msg.put_pack('nnnnnn',
                       @id,
                       (@qr & 1) << 15 |
                       (@opcode & 15) << 11 |
                       (@aa & 1) << 10 |
                       (@tc & 1) << 9 |
                       (@rd & 1) << 8 |
                       (@ra & 1) << 7 |
                       (@rcode & 15),
                       @question.length,
                       @answer.length,
                       @authority.length,
                       @additional.length)
          @question.each {|q|
            name, typeclass = q
            msg.put_name(name)
            msg.put_pack('nn', typeclass::TypeValue, typeclass::ClassValue)
          }
          [@answer, @authority, @additional].each {|rr|
            rr.each {|r|
              name, ttl, data = r
              msg.put_name(name)
              msg.put_pack('nnN', data.class::TypeValue, data.class::ClassValue, ttl)
              msg.put_length16 {data.encode_rdata(msg)}
            }
          }
        }.to_s
      end

      class MessageEncoder
        def initialize
          @data = ''
          @names = {}
          yield self
        end

        def to_s
          return @data
        end

        def put_bytes(d)
          @data << d
        end

        def put_pack(template, *d)
          @data << d.pack(template)
        end

        def put_length16
          length_index = @data.length
          @data << "\0\0"
          data_start = @data.length
          yield
          data_end = @data.length
          @data[length_index, 2] = [data_end - data_start].pack("n")
        end

        def put_string(d)
          self.put_pack("C", d.length)
          @data << d
        end

        def put_name(d)
          put_labels(d.to_a)
        end

        def put_labels(d)
          d.each_index {|i|
            domain = d[i..-1]
            if idx = @names[domain]
              self.put_pack("n", 0xc000 | idx)
              return
            else
              @names[domain] = @data.length
              self.put_label(d[i])
            end
          }
          @data << "\0"
        end

        def put_label(d)
          self.put_string(d.string)
        end
      end

      def Message.decode(m)
        o = Message.new(0)
        MessageDecoder.new(m) {|msg|
          id, flag, qdcount, ancount, nscount, arcount =
            msg.get_unpack('nnnnnn')
          o.id = id
          o.qr = (flag >> 15) & 1
          o.opcode = (flag >> 11) & 15
          o.aa = (flag >> 10) & 1
          o.tc = (flag >> 9) & 1
          o.rd = (flag >> 8) & 1
          o.ra = (flag >> 7) & 1
          o.rcode = flag & 15
          (1..qdcount).each {
            name, typeclass = msg.get_question
            o.add_question(name, typeclass)
          }
          (1..ancount).each {
            name, ttl, data = msg.get_rr
            o.add_answer(name, ttl, data)
          }
          (1..nscount).each {
            name, ttl, data = msg.get_rr
            o.add_authority(name, ttl, data)
          }
          (1..arcount).each {
            name, ttl, data = msg.get_rr
            o.add_additional(name, ttl, data)
          }
        }
        return o
      end

      class MessageDecoder
        def initialize(data)
          @data = data
          @index = 0
          @limit = data.length
          yield self
        end

        def get_length16
          len, = self.get_unpack('n')
          save_limit = @limit
          @limit = @index + len
          d = yield len
          if @index < @limit
            raise DecodeError.new("junk exist")
          elsif @limit < @index
            raise DecodeError.new("limit exceed")
          end
          @limit = save_limit
          return d
        end

        def get_bytes(len = @limit - @index)
          d = @data[@index, len]
          @index += len
          return d
        end

        def get_unpack(template)
          len = 0
          template.each_byte {|byte|
            case byte
            when ?c, ?C
              len += 1
            when ?n
              len += 2
            when ?N
              len += 4
            else
              raise StandardError.new("unsupported template: '#{byte.chr}' in '#{template}'")
            end
          }
          raise DecodeError.new("limit exceed") if @limit < @index + len
          arr = @data.unpack("@#{@index}#{template}")
          @index += len
          return arr
        end

        def get_string
          len = @data[@index]
          raise DecodeError.new("limit exceed") if @limit < @index + 1 + len
          d = @data[@index + 1, len]
          @index += 1 + len
          return d
        end

        def get_name
          return Name.new(self.get_labels)
        end

        def get_labels(limit=nil)
          limit = @index if !limit || @index < limit
          d = []
          while true
            case @data[@index]
            when 0
              @index += 1
              return d
            when 192..255
              idx = self.get_unpack('n')[0] & 0x3fff
              if limit <= idx
                raise DecodeError.new("non-backward name pointer")
              end
              save_index = @index
              @index = idx
              d += self.get_labels(limit)
              @index = save_index
              return d
            else
              d << self.get_label
            end
          end
          return d
        end

        def get_label
          return Label::Str.new(self.get_string)
        end

        def get_question
          name = self.get_name
          type, klass = self.get_unpack("nn")
          return name, Resource.get_class(type, klass)
        end

        def get_rr
          name = self.get_name
          type, klass, ttl = self.get_unpack('nnN')
          typeclass = Resource.get_class(type, klass)
          return name, ttl, self.get_length16 {typeclass.decode_rdata(self)}
        end
      end
    end

    class Query
      def encode_rdata(msg)
        raise EncodeError.new("#{self.type} is query.") 
      end

      def self.decode_rdata(msg)
        raise DecodeError.new("#{self.type} is query.") 
      end
    end

    class Resource < Query
      ClassHash = {}

      def encode_rdata(msg)
        raise NotImplementedError.new
      end

      def self.decode_rdata(msg)
        raise NotImplementedError.new
      end

      def ==(other)
        return self.type == other.type &&
          self.instance_variables == other.instance_variables &&
          self.instance_variables.collect {|name| self.instance_eval name} ==
          other.instance_variables.collect {|name| other.instance_eval name}
      end

      def eql?(other)
        return self == other
      end

      def hash
        h = 0
        self.instance_variables.each {|name|
          h += self.instance_eval("#{name}.hash")
        }
        return h
      end

      def self.get_class(type_value, class_value)
        return ClassHash[[type_value, class_value]] ||
          Generic.create(type_value, class_value)
      end

      class Generic < Resource
        def initialize(data)
          @data = data
        end
        attr_reader :data

        def encode_rdata(msg)
          msg.put_bytes(data)
        end

        def self.decode_rdata(msg)
          return self.new(msg.get_bytes)
        end

        def self.create(type_value, class_value)
          c = Class.new(Generic)
          c.const_set(:TypeValue, type_value)
          c.const_set(:ClassValue, class_value)
          Generic.const_set("Type#{type_value}_Class#{class_value}", c)
          ClassHash[[type_value, class_value]] = c
          return c
        end
      end

      class DomainName < Resource
        def initialize(name)
          @name = name
        end
        attr_reader :name

        def encode_rdata(msg)
          msg.put_name(@name)
        end

        def self.decode_rdata(msg)
          return self.new(msg.get_name)
        end
      end

      # Standard (class generic) RRs
      ClassValue = nil

      class NS < DomainName
        TypeValue = 2
      end

      class CNAME < DomainName
        TypeValue = 5
      end

      class SOA < Resource
        TypeValue = 6

        def initialize(mname, rname, serial, refresh, retry_, expire, minimum)
          @mname = mname
          @rname = rname
          @serial = serial
          @refresh = refresh
          @retry = retry_
          @expire = expire
          @minimum = minimum
        end
        attr_reader :mname, :rname, :serial, :refresh, :retry, :expire, :minimum

        def encode_rdata(msg)
          msg.put_name(@mname)
          msg.put_name(@rname)
          msg.put_pack('NNNNN', @serial, @refresh, @retry, @expire, @minimum)
        end

        def self.decode_rdata(msg)
          mname = msg.get_name
          rname = msg.get_name
          serial, refresh, retry_, expire, minimum = msg.get_unpack('NNNNN')
          return self.new(
                          mname, rname, serial, refresh, retry_, expire, minimum)
        end
      end

      class PTR < DomainName
        TypeValue = 12
      end

      class HINFO < Resource
        TypeValue = 13

        def initialize(cpu, os)
          @cpu = cpu
          @os = os
        end
        attr_reader :cpu, :os

        def encode_rdata(msg)
          msg.put_string(@cpu)
          msg.put_string(@os)
        end

        def self.decode_rdata(msg)
          cpu = msg.get_string
          os = msg.get_string
          return self.new(cpu, os)
        end
      end

      class MINFO < Resource
        TypeValue = 14

        def initialize(rmailbx, emailbx)
          @rmailbx = rmailbx
          @emailbx = emailbx
        end
        attr_reader :rmailbx, :emailbx

        def encode_rdata(msg)
          msg.put_name(@rmailbx)
          msg.put_name(@emailbx)
        end

        def self.decode_rdata(msg)
          rmailbx = msg.get_string
          emailbx = msg.get_string
          return self.new(rmailbx, emailbx)
        end
      end

      class MX < Resource
        TypeValue= 15

        def initialize(preference, exchange)
          @preference = preference
          @exchange = exchange
        end
        attr_reader :preference, :exchange

        def encode_rdata(msg)
          msg.put_pack('n', @preference)
          msg.put_name(@exchange)
        end

        def self.decode_rdata(msg)
          preference, = msg.get_unpack('n')
          exchange = msg.get_name
          return self.new(preference, exchange)
        end
      end

      class TXT < Resource
        TypeValue = 16

        def initialize(data)
          @data = data
        end
        attr_reader :data

        def encode_rdata(msg)
          msg.put_string(@data)
        end

        def self.decode_rdata(msg)
          data = msg.get_string
          return self.new(data)
        end
      end

      class ANY < Query
        TypeValue = 255
      end

      ClassInsensitiveTypes = [
        NS, CNAME, SOA, PTR, HINFO, MINFO, MX, TXT, ANY
      ]

      # ARPA Internet specific RRs
      module IN
        ClassValue = 1

        ClassInsensitiveTypes.each {|s|
          c = Class.new(s)
          c.const_set(:TypeValue, s::TypeValue)
          c.const_set(:ClassValue, ClassValue)
          ClassHash[[s::TypeValue, ClassValue]] = c
          self.const_set(s.name.sub(/.*::/, ''), c)
        }

        class A < Resource
          ClassHash[[TypeValue = 1, ClassValue = ClassValue]] = self

          def initialize(address)
            @address = IPv4.create(address)
          end
          attr_reader :address

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg)
            return self.new(IPv4.new(msg.get_bytes(4)))
          end
        end

        class WKS < Resource
          ClassHash[[TypeValue = 11, ClassValue = ClassValue]] = self

          def initialize(address, protocol, bitmap)
            @address = IPv4.create(address)
            @protocol = protocol
            @bitmap = bitmap
          end
          attr_reader :address, :protocol, :bitmap

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
            msg.put_pack("n", @protocol)
            msg.put_bytes(@bitmap)
          end

          def self.decode_rdata(msg)
            address = IPv4.new(msg.get_bytes(4))
            protocol, = msg.get_unpack("n")
            bitmap = msg.get_bytes
            return self.new(address, protocol, bitmap)
          end
        end

        class AAAA < Resource
          ClassHash[[TypeValue = 28, ClassValue = ClassValue]] = self

          def initialize(address)
            @address = IPv6.create(address)
          end
          attr_reader :address

          def encode_rdata(msg)
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg)
            return self.new(IPv6.new(msg.get_bytes(16)))
          end
        end
      end
    end
  end
end

