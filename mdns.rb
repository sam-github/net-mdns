#!/opt/local/bin/ruby -w

$:.unshift(File.dirname($0))

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
opt_type = Resolv::DNS::Resource::IN::ANY

opts = GetoptLong.new(
  [ "--help",    "-h",              GetoptLong::NO_ARGUMENT ],
  [ "--type",    "-t",              GetoptLong::REQUIRED_ARGUMENT],
  [ "--debug",   "-d",              GetoptLong::NO_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
    when "--help"  then puts HELP; exit 0
    when "--debug" then opt_debug = true
    when "--type"  then opt_type = rrmap[arg]
  end
end

r = Resolv::MDNS.new

r.lazy_initialize

Name = Resolv::DNS::Name

ARGV.each do |n|
  argv0 = Name.create(n)

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

  puts "#{n} -> #{argv0}"

# r.each_resource(argv0, opt_type) do |rr| # BUG - this never times out...
  r.getresources(argv0, opt_type).each do |rr|
    case rr
    when Resolv::DNS::Resource::IN::PTR
      n = rr.name

      puts "type=#{argv0} instance=#{n}"

      r.each_resource(n, Resolv::DNS::Resource::IN::ANY) do |rr1|
        pp rr1
      end
    else
      pp rr
    end
  end
end

