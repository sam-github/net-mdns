
class Str < String
  def hash; self.downcase.hash; end
end

h = { }

k = Str.new('a')

k == 'A'
'A' == k

h[k] = 'lower'

k = Str.new('A')
p k.downcase
p k.downcase.class
p k.downcase.hash
k.hash == 'a'.hash

h.has_key? k


class Sub
end


