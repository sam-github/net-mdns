
require 'resolv.rb'

Name = Resolv::DNS::Name

def equals0(s, n)
  if n.absolute? && s[-1] != ?.
     s += '.'
  end

  Name.create(s) == n
end


