

class String
  def brackets
    self.class.new("(" + self + ")")
  end
end
    
class Str < String
  def initialize(s)
    puts '!Str'
    super(s)
  end
end


class Now < String
  def initialize
    puts '!Now'
    super(Time.now.to_s)
  end
end

class Now2 < String
  def initialize(a,b)
    puts "!Now2 #{a} #{b}"
    super(Time.now.to_s)
  end
end

Str.new('aa').upcase
Str.new('aa').upcase.class
Now.new.upcase
Now.new.upcase.class
Now2.new(1,2).upcase
Now2.new(1,2).upcase.class

Str.new('aa').brackets
Now.new.brackets
Now2.new(1,2).brackets


Str.new('aa').to_s.class
Now.new.to_s.class
Now2.new(1,2).to_s.class


