#!/usr/local/bin/ruby18 -wI../ruby/lib

$: << File.dirname($0)

require 'getoptlong'
require 'net/dns/mdns'
require 'pp'

rrmap = {
  'a'   => Resolv::DNS::Resource::IN::A,
  'any' => Resolv::DNS::Resource::IN::ANY,
  'ptr' => Resolv::DNS::Resource::IN::PTR,
  'srv' => Resolv::DNS::Resource::IN::SRV,
  nil   => Resolv::DNS::Resource::IN::ANY
}

rtypes = rrmap.keys.join ', '

HELP =<<EOF
Usage: mdns [options] name [record-type]

Options
  -h,--help      Print this helpful message.
  -d,--debug     Print debug information.

Supported record types are:
  #{rrmap.keys.compact.join "\n  "}

Default is 'any'.

Examples:
EOF

opt_debug = nil
opt_svc = nil

opts = GetoptLong.new(
  [ "--help",    "-h",              GetoptLong::NO_ARGUMENT ],
  [ "--svc",     "-s",              GetoptLong::NO_ARGUMENT ],
  [ "--debug",   "-d",              GetoptLong::NO_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
    when "--help" then
      puts HELP
      exit 0

    when "--debug" then
      opt_debug = true

    when "--svc"
      opt_svc = true
  end
end

r = Resolv::MDNS.new

r.lazy_initialize

if opt_debug
  pp r
end

Name = Resolv::DNS::Name

argv0 = Name.create(ARGV[0])

unless argv0.absolute?
  if argv0.to_s[0] == ?_
    if argv0.length == 1
      argv0 = Name.create(argv0.to_s + '._tcp')
    end

    if argv0.length == 2
      argv0 = Name.create(argv0.to_s + '.local')
    end
  else
    if argv0.length == 1
      argv0 = Name.create(argv0.to_s + '.local')
    end
  end
end

rrs = r.getresources(argv0, rrmap[ARGV[1]])

if !opt_svc
  pp rrs
  exit 0
end


rrs.each do |rr|
  if(Resolv::DNS::Resource::IN::PTR === rr)
    n = rr.name

    puts "type=#{ARGV[0]} instance=#{n}"

    r.each_resource(n, Resolv::DNS::Resource::IN::ANY) do |svcrr|
      case svcrr
      when Resolv::DNS::Resource::IN::SRV
        puts('  ' + svcrr.inspect)

      when Resolv::DNS::Resource::IN::TXT
        puts('  IN::TXT ' + svcrr.data)
      else
        # unexpected!
        pp svcrr
      end
    end
  end
end

