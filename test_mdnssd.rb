#!/usr/bin/ruby -w

$:.unshift File.dirname($0)

require 'net/dns/mdnssd.rb'
require 'test/unit'

require 'pp'

include Net::DNS

class TestMdnssd < Test::Unit::TestCase


  def test_strings_parse
    strings = [
      '=',
      '= a',
      "\x01=v",
      'a',
      'A=V',
      'B=',
      'b=V',
      'c= ',
      'C=V',
      ' A= \x01\x02\x03',
      ' b= \x03\x02\x01'
    ]
    hash = {
      'a' => nil,
      'b' => '',
      'c' => ' ',
      ' a' => ' \x01\x02\x03',
      ' b' => ' \x03\x02\x01'
    }

    h = MDNSSD::Util.parse_strings(strings)

    assert_equal(hash, h)
  end


end

