
class Foo
  attr_accessor :foo
  def initialize(foo)
    @foo = foo
  end
end

"%x" % Foo.new(1).hash
"%x" % Foo.new(1).hash
"%x" % Foo.new(2).hash


