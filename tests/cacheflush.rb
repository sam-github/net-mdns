require 'resolv.rb'
require 'pp'

class Resolv
  class DNS
    class Name
      def inspect
        to_s + (absolute? ? '.' : '')
      end
    end
  end
end

data1 = "\000\000\204\000\000\000\000\002\000\000\000\001\010ensemble\005_http\004_tcp\005local\000\000!\200\001\000\000\000<\000\021\000\000\000\000\000P\010ensemble\300 \300\f\000\020\200\001\000\000\000<\000\001\000\3007\000\001\200\001\000\000\000<\000\004\300\250{\232"

msg = Resolv::DNS::Message.decode(data1)

pp msg

