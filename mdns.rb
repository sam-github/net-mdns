#!/usr/local/bin/ruby18 -wI../ruby/lib

$: << File.dirname($0)

require 'getoptlong'
require 'multicast'
require 'pp'

rrmap = {
  'any' => Resolv::DNS::Resource::IN::ANY,
  'a'   => Resolv::DNS::Resource::IN::A,
  'ptr' => Resolv::DNS::Resource::IN::PTR,
# 'srv' => Resolv::DNS::Resource::IN::ANY,

  nil   => Resolv::DNS::Resource::IN::ANY
}

HELP =<<EOF
Usage: mdns [options] name [record-type]

Options
  -h,--help      Print this helpful message.
  -d,--debug     Print debug information.

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
  pp Resolv
end

rrs = r.getresources(ARGV[0], rrmap[ARGV[1]])

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

