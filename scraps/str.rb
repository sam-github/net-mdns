
require './net/dns/resolvx.rb'

Str = Resolv::DNS::Label::Str

h = { }

k = Str.new('a')

k == 'A'
'A' == k

h[k] = 'lower'

k = Str.new('A')
k.
k.hash
k.hash == 'a'.hash

h.has_key? k

