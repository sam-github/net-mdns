class Foo
 attr_writer :opt
 def initialize
   yield self

   class < self
     remove_method 'opt='
   end
 end
end

f = Foo.new { |a| a.opt = 4 }

f.opt= 1

