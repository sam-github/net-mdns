#!/usr/local/bin/ruby18 -w

$:.unshift(File.dirname($0))

require 'getoptlong'

require 'net/dns/mdns-sd.rb'

# TODO - see if I can use DNSSD from require 'dnssd'
DNSSD = Net::DNS::DNSSD

rrmap = {
  'a'   => Resolv::DNS::Resource::IN::A,
  'any' => Resolv::DNS::Resource::IN::ANY,
  'ptr' => Resolv::DNS::Resource::IN::PTR,
  'srv' => Resolv::DNS::Resource::IN::SRV,
  nil   => Resolv::DNS::Resource::IN::ANY
}

rtypes = rrmap.keys.join ', '

=begin
Apple's dns-sd options:

  mdns -e                  (Enumerate recommended registration domains)
  mdns -f                      (Enumerate recommended browsing domains)
  mdns -b        <Type> <Domain>         (Browse for service instances)
  mdns -l <Name> <Type> <Domain>           (Look up a service instance)
  mdns -r <Name> <Type> <Domain> <Port> [<TXT>...] (Register a service)
  mdns -p <Name> <Type> <Domain> <Port> <Host> <IP> [<TXT>...]  (Proxy)
  mdns -q <FQDN> <rrtype> <rrclass> (Generic query for any record type)
=end

@debug = false

@recursive = false
@domain = 'local'
@type = nil
@name = nil
@port = nil
@txt  = {}

@cmd = nil


HELP =<<EOF
Usage: 
  mdns -B        <Type> [Domain]         (Browse for service instances)
  mdns -L <Name> <Type> [Domain]           (Look up a service instance)
  mdns -R <Name> <Type> [Domain] <Port> [<TXT>...] (Register a service)

[Domain] is optional for -B, -L, and -R, it defaults to "local".

[<TXT>...] is optional for -R, it can be a series of key=value pairs.

You can use long names --browse, --lookup, and --register instead of -B, -L,
and -R.

Examples:
  mdns -B _daap._tcp
  mdns -L sam _daap._tcp
  mdns -R me _example._tcp local 4321 key=value key2=value2
EOF

opts = GetoptLong.new(
  [ "--debug",    "-d",               GetoptLong::NO_ARGUMENT ],
  [ "--help",     "-h",               GetoptLong::NO_ARGUMENT ],

  [ "--browse",    "-B",              GetoptLong::NO_ARGUMENT ],
  [ "--lookup",    "-L",              GetoptLong::NO_ARGUMENT ],
  [ "--register",  "-R",              GetoptLong::NO_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
  when "--debug"
    @debug = true
    require 'pp'

  when "--help"
    print HELP
    exit 0

  when "--browse"
    @cmd = :browse
    @type   = ARGV.shift
    @domain = ARGV.shift || @domain

  when "--lookup"
    @cmd = :lookup
    @name   = ARGV.shift
    @type   = ARGV.shift
    @domain = ARGV.shift || @domain

  when "--register"
    @cmd = :register
    @name   = ARGV.shift
    @type   = ARGV.shift
    @port   = ARGV.shift
    if @port.to_i == 0
      @domain = @port
      @port = ARGV.shift.to_i
    else
      @port = @port.to_i
    end
    ARGV.each do |kv|
      kv.match(/([^=]+)=([^=]+)/)
      @txt[$1] = $2
    end
    ARGV.replace([])
  end
end

unless @cmd
  print HELP
  exit 1
end

pp( @cmd, @type, @domain )  if @debug

case @cmd
when :browse
  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name"

  handle = DNSSD.browse(@type, @domain) do |reply|
    printf fmt, "?", reply.domain, reply.type, reply.name
  end

  $stdin.gets
  handle.stop


when :lookup
  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.resolve(@name, @type, @domain) do |reply|
    location = "#{reply.target}:#{reply.port}"
    text = reply.text_record.to_a.map { |kv| kv.join('=') }.join(', ')
    printf fmt, "?", reply.domain, reply.type, reply.name, location, text
  end

  $stdin.gets
  handle.stop

when :register
  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.register(@name, @type, @domain, @port, @txt) do |notice|
    location = "#{Socket.gethostname}:#{@port}"
    text = @txt.to_a.map { |kv| kv.join('=') }.join(', ')
    printf fmt, "?", notice.domain, notice.type, notice.name, location, text
  end

  $stdin.gets
  handle.stop

end

