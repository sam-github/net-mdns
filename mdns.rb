#!/usr/local/bin/ruby18 -w
# This is an example illustrating how to use the DNSSD APIs.
#
# Author: Sam Roberts <sroberts@uniserve.com>
# Copyright: I place it in the public domain

$:.unshift(File.dirname($0))

require 'getoptlong'

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
  mdns [options] -B        <Type> [Domain]         (Browse for service instances)
  mdns [options] -L <Name> <Type> [Domain]           (Look up a service instance)
  mdns [options] -R <Name> <Type> [Domain] <Port> [<TXT>...] (Register a service)

[Domain] is optional for -B, -L, and -R, it defaults to "local".

[<TXT>...] is optional for -R, it can be a series of key=value pairs.

You can use long names --browse, --lookup, and --register instead of -B, -L,
and -R.

Options:
  --native   Attempt to use 'dnssd', the interface to the native DNS-SD
             resolver library.
  --ruby     Attempt to use 'net/dns/mdns-sd', a pure-ruby DNS-SD resolver
             library.

Examples:
  mdns -B _daap._tcp
  mdns -L sam _daap._tcp
  mdns -R me _example._tcp local 4321 key=value key2=value2
EOF

opts = GetoptLong.new(
  [ "--debug",    "-d",               GetoptLong::NO_ARGUMENT ],
  [ "--help",     "-h",               GetoptLong::NO_ARGUMENT ],
  [ "--native",   "-n",               GetoptLong::NO_ARGUMENT ],
  [ "--ruby",     "-r",               GetoptLong::NO_ARGUMENT ],

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
  require 'net/dns/mdns-sd.rb'
  DNSSD = Net::DNS::DNSSD
  puts "Using net::dns::DNSSD..."
end

unless @cmd
  print HELP
  exit 1
end

case @cmd
when :browse
  pp( @cmd, @type, @domain )  if @debug

  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name"

  handle = DNSSD.browse(@type, @domain) do |reply|
    pp reply if @debug

    printf fmt, "?", reply.domain, reply.type, reply.name
  end

  $stdin.gets
  handle.stop


when :lookup
  pp( @cmd, @name, @type, @domain )  if @debug

  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.resolve(@name, @type, @domain) do |reply|
    pp reply if @debug

    location = "#{reply.target}:#{reply.port}"
    text = reply.text_record.to_a.map { |kv| kv.join('=') }.join(', ')
    printf fmt, "?", reply.domain, reply.type, reply.name, location, text
  end

  $stdin.gets
  handle.stop

when :register
  pp( @cmd, @name, @type, @domain, @port, @txt)  if @debug

  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name", "Location", "Text"

  handle = DNSSD.register(@name, @type, @domain, @port, @txt) do |notice|
    pp notice if @debug

    location = "#{Socket.gethostname}:#{@port}"
    text = @txt.to_a.map { |kv| kv.join('=') }.join(', ')
    printf fmt, "?", notice.domain, notice.type, notice.name, location, text
  end

  $stdin.gets
  handle.stop

end

