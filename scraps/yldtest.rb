

$array = [
  [ 1, 2, "a" ],
  [ 3, 4, "b" ],
];

def yield0
  $array.each do |ary|
    yield ary
  end
end


yield0 { |a| p "ary #{a.inspect}" }
yield0 { |a,b| p "ary #{a}, #{b}" }
yield0 { |a,b,c| p "ary #{a}, #{b}, #{c}" }
yield0 { |a,b,c,d| p "ary #{a}, #{b}, #{c}, #{d.inspect}" }
yield0 { |a,b,c,d,e| p "ary #{a}, #{b}, #{c}, #{d.inspect}, #{e.inspect}" }


