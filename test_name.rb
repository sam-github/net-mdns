#!/usr/bin/ruby -w

$:.unshift File.dirname($0)

require 'net/dns/resolvx.rb'
require 'test/unit'

require 'pp'

Name = Resolv::DNS::Name

class TestDnsName < Test::Unit::TestCase

  def test_what_I_think_are_odd_behaviours
    # Why can't test against strings?
    assert_equal(false, Name.create("example.CoM") ==   "example.com")
    assert_equal(false, Name.create("example.CoM").eql?("example.com"))

    # Why does making it absolute mean they aren't equal?
    assert_equal(false, Name.create("example.CoM").eql?(Name.create("example.com.")))
    assert_equal(false, Name.create("example.CoM") ==   Name.create("example.com."))
  end

  def test_CoMparisons

    assert_equal(true,  Name.create("example.CoM").eql?(Name.create("example.com")))
    assert_equal(true,  Name.create("example.CoM") ==   Name.create("example.com"))

    assert_equal(true,  Name.create("example.CoM").equal?("example.com."))
    assert_equal(true,  Name.create("example.CoM").equal?("example.com"))

    assert_equal(true,  Name.create("www.example.CoM") <   "example.com")
    assert_equal(true,  Name.create("www.example.CoM") <=  "example.com")
    assert_equal(-1,    Name.create("www.example.CoM") <=> "example.com")
    assert_equal(false, Name.create("www.example.CoM") >=  "example.com")
    assert_equal(false, Name.create("www.example.CoM") >   "example.com")

    assert_equal(false, Name.create("example.CoM") <   "example.com")
    assert_equal(true,  Name.create("example.CoM") <=  "example.com")
    assert_equal(0,     Name.create("example.CoM") <=> "example.com")
    assert_equal(true,  Name.create("example.CoM") >=  "example.com")
    assert_equal(false, Name.create("example.CoM") >   "example.com")

    assert_equal(false, Name.create("CoM") <   "example.com")
    assert_equal(false, Name.create("CoM") <=  "example.com")
    assert_equal(+1,    Name.create("CoM") <=> "example.com")
    assert_equal(true,  Name.create("CoM") >=  "example.com")
    assert_equal(true,  Name.create("CoM") >   "example.com")

    assert_equal(nil,   Name.create("bar.CoM") <   "example.com")
    assert_equal(nil,   Name.create("bar.CoM") <=  "example.com")
    assert_equal(nil,   Name.create("bar.CoM") <=> "example.com")
    assert_equal(nil,   Name.create("bar.CoM") >=  "example.com")
    assert_equal(nil,   Name.create("bar.CoM") >   "example.com")

    assert_equal(nil,   Name.create("net.") <   "com")
    assert_equal(nil,   Name.create("net.") <=  "com")
    assert_equal(nil,   Name.create("net.") <=> "com")
    assert_equal(nil,   Name.create("net.") >=  "com")
    assert_equal(nil,   Name.create("net.") >   "com")

  end
end

