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
@type = '_http._tcp'
@name = nil
@port = 9999
@host = Socket.gethostname
@ip   = nil # TODO

@cmd = nil


HELP =<<EOF
Usage: 
  mdns -b        <Type> <Domain>         (Browse for service instances)
  mdns -l <Name> <Type> <Domain>           (Look up a service instance)

Many arguments are optional and have defaults:
  Type     - #{@type}
  Domain   - #{@domain}

Examples:
  mdns -b _daap._tcp                      (Browse for iTunes instances)
EOF

opts = GetoptLong.new(
  [ "--debug",    "-d",               GetoptLong::NO_ARGUMENT ],
  [ "--help",     "-h",               GetoptLong::NO_ARGUMENT ],

  [ "--browse",    "-b",              GetoptLong::NO_ARGUMENT ],
  [ "--lookup",    "-l",              GetoptLong::NO_ARGUMENT ]
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
    @type   = ARGV.shift || @type
    @domain = ARGV.shift || @domain

  when "--lookup"
    @cmd = :lookup
    @name   = ARGV.shift || @name
    @type   = ARGV.shift || @type
    @domain = ARGV.shift || @domain
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

  q = DNSSD.browse(@type, @domain) do |reply|
    printf fmt, "?", reply.domain, reply.type, reply.name
  end

  $stdin.gets
  q.stop


when :lookup
  fmt = "%-3.3s  %-10.10s   %-15.15s  %-20.20s %-20.20s %s\n"
  printf fmt, "Ifx", "Domain", "Service Type", "Instance Name", "Location", "Text"

  q = DNSSD.resolve(@name, @type, @domain) do |reply|
    location = "#{reply.target}:#{reply.port}"
    text = reply.text_record.map { |s| s.inspect }.join(', ')
    printf fmt, "?", reply.domain, reply.type, reply.name, location, text
  end

  $stdin.gets
  q.stop


end

