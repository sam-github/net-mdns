
class Str
  def to_str; 'str'; end
# def eql?(s); true; end
# def ==(s); true; end
  def eql?(s); true; end
# def <=>(s); 0; end
end

p Str.new == 'a'
p 'a' == Str.new

p Str.new.eql?('a')
p 'a'.eql?(Str.new)

p Str.new <=> 'a'
p 'a' <=> Str.new

