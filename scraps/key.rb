

h = { }

class Key < String
  def hash; self.downcase.hash; end
end

k = Key.new('a')

k == 'A'
'A' == ke
k.hash == 'A'.hash

h[k] = 'lower'

k = DnssdKey.new('A')

h.has_key? k

