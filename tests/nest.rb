#!/opt/local/bin/ruby -w

$: << File.dirname($0)

require 'resolv'
require 'pp'

r = Resolv::DNS.new

r.lazy_initialize

Name = Resolv::DNS::Name

ARGV.each do |n|
  argv0 = Name.create(n)

  puts "query #{argv0.to_s}"

  r.each_resource(argv0, Resolv::DNS::Resource::IN::ANY) do |rr|
# r.getresources(argv0, Resolv::DNS::Resource::IN::ANY).each do |rr|
    pp rr

    case rr
    when Resolv::DNS::Resource::IN::NS
      n = rr.name

      puts "inner query #{n.to_s}"
      r.each_resource(n, Resolv::DNS::Resource::IN::ANY) do |rr1|
        pp rr1
      end
    end
  end
end

