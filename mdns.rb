#!/usr/local/bin/ruby18 -w
# This is an example illustrating how to use the DNSSD APIs.
#
# Author: Sam Roberts <sroberts@uniserve.com>
# Copyright: I place it in the public domain

$:.unshift(File.dirname($0))

require 'getoptlong'

$stdout.sync = true
$stderr.sync = true

=begin
Apple's dns-sd options:

  mdns -E                  (Enumerate recommended registration domains)
  mdns -F                      (Enumerate recommended browsing domains)
  mdns -B        <Type> <Domain>         (Browse for service instances)
  mdns -L <Name> <Type> <Domain>           (Look up a service instance)
  mdns -R <Name> <Type> <Domain> <Port> [<TXT>...] (Register a service)
  mdns -P <Name> <Type> <Domain> <Port> <Host> <IP> [<TXT>...]  (Proxy)
  mdns -Q <FQDN> <rrtype> <rrclass> (Generic query for any record type)
=end

@debug = false
@log   = nil

@recursive = false
@domain = 'local'
@type = nil
@name = nil
@port = nil
@txt  = {}

@cmd = nil


# TODO - can I use introspection on class names to determine all supported
# RR types in DNS::Resource::IN?

HELP =<<EOF
Usage: 
  mdns [options] -B        <type> [domain]         (Browse for service instances)
  mdns [options] -L <name> <type> [domain]           (Look up a service instance)
  mdns [options] -R <name> <type> [domain] <port> [<TXT>...] (Register a service)
  mdns [options] -Q <fqdn> [rrtype] [rrclass] (Generic query for any record type)

Note: -Q is not yet implemented.

For -B, -L, and -R, [domain] is optional and defaults to "local".

For -Q, [rrtype] defaults to A, other values are TXT, PTR, SRV, CNAME, ...

For -Q, [rrclass] defaults to 1 (IN).


[<TXT>...] is optional for -R, it can be a series of key=value pairs.

You can use long names --browse, --lookup, and --register instead of -B, -L,
and -R.

Options:
  -m,--mdnssd   Attempt to use 'net/dns/mdnssd', a pure-ruby DNS-SD resolver
                library (this is the default).
  -n,--dnssd    Attempt to use 'dnssd', the interface to the native ("-n")
                DNS-SD resolver library APIs, "dns_sd.h" from Apple.
                Note: YMMV, this doesn't entirely work, currently.
  -d,--debug    Print debug messages to stderr.

Examples:
  mdns -B _daap._tcp
  mdns -L sam _daap._tcp
  mdns -R me _example._tcp local 4321 key=value key2=value2
EOF

opts = GetoptLong.new(
  [ "--debug",    "-d",               GetoptLong::NO_ARGUMENT ],
  [ "--help",     "-h",               GetoptLong::NO_ARGUMENT ],
  [ "--dnssd",    "-n",               GetoptLong::NO_ARGUMENT ],
  [ "--mdnssd",   "-m",               GetoptLong::NO_ARGUMENT ],

  [ "--browse",    "-B",              GetoptLong::NO_ARGUMENT ],
  [ "--lookup",    "-L",              GetoptLong::NO_ARGUMENT ],
  [ "--register",  "-R",              GetoptLong::NO_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
  when "--debug"
    require 'pp'
    require 'logger'

    @debug = true
    @log = Logger.new(STDERR)
    @log.level = Logger::DEBUG

  when "--help"
    print HELP
    exit 0

  when '--native'
    require 'dnssd'

  when "--browse"
    @cmd = :browse
    @type   = ARGV.shift
    @domain = ARGV.shift || @domain

  when "--lookup"
    @cmd = :lookup
    @name   = ARGV.shift
    @type   = ARGV.shift
    @domain = ARGV.shift || @domain

    unless @name && @type
      puts 'name and type required for -L'
      exit 1
    end

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

begin
  DNSSD.class
  puts "Using native DNSSD..."
rescue NameError
  require 'net/dns/mdnssd.rb'
  DNSSD = Net::DNS::MDNSSD
  Net::DNS::MDNS::Responder.instance.log = @log if @log
  puts "Using net::dns::MDNSSD..."
end

unless @cmd
  print HELP
  exit 1
end

case @cmd
when :browse
  STDERR.puts( "#{@cmd}(#{@type}, #{@domain}) =>" )  if @debug

  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name"

  handle = DNSSD.browse(@type, @domain) do |reply|
    printf fmt, "?", reply.domain, reply.type, reply.name
  end

  $stdin.gets
  handle.stop


when :lookup
  STDERR.puts( "#{@cmd}(#{@name}, #{@type}, #{@domain}) =>" )  if @debug

  fmt = "%-3.3s  %-8.8s   %-19.19s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ttl", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.resolve(@name, @type, @domain) do |reply|
    location = "#{reply.target}:#{reply.port}"
    text = reply.text_record.to_a.map { |kv| "#{kv[0]}=#{kv[1].inspect}" }.join(', ')
    printf fmt, reply.ttl, reply.domain, reply.type, reply.name, location, text
  end

  $stdin.gets
  handle.stop

when :register
  pp( @cmd, @name, @type, @domain, @port, @txt)  if @debug

  fmt = "%-3.3s  %-8.8s   %-19.19s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ttl", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.register(@name, @type, @domain, @port, @txt) do |notice|
    location = "#{Socket.gethostname}:#{@port}"
    text = @txt.to_a.map { |kv| "#{kv[0]}=#{kv[1].inspect}" }.join(', ')
    printf fmt, notice.ttl, notice.domain, notice.type, notice.name, location, text
  end

  $stdin.gets
  handle.stop

end

