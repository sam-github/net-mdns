#!/usr/local/bin/ruby18 -wI../ruby/lib

require 'multicast'
require 'pp'

rrmap = {
  'any' => Resolv::DNS::Resource::IN::ANY,
  'a'   => Resolv::DNS::Resource::IN::A,
  'ptr' => Resolv::DNS::Resource::IN::PTR,
# 'srv' => Resolv::DNS::Resource::IN::ANY,

  nil   => Resolv::DNS::Resource::IN::ANY
}

r = Resolv::MDNS.new

r.lazy_initialize

#pp Resolv

pp r.getresources(ARGV[0], rrmap[ARGV[1]])

