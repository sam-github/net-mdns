require 'rubygems'

Gem.manage_gems

spec = Gem::Specification.new do |s|
  s.name = 'net-mdns'
  s.version = "0.4"
  s.author = "Sam Roberts"
  s.email = "sroberts@uniserve.com"
  s.homepage = "http://dnssd.rubyforge.org/net-mdns/"
  s.summary = "DNS-SD and mDNS implementation for ruby"
  s.platform = Gem::Platform::RUBY
  s.files = Dir.glob("lib/net/**/*.rb")
  s.require_path = 'lib'  
end

if $0==__FILE__
  Gem::Builder.new(spec).build
end
