#!/usr/bin/ruby -w

$:.unshift File.dirname($0)

require 'net/dns/resolv-mdns.rb'
require 'test/unit'

require 'pp'

class TestResolvMdns < Test::Unit::TestCase


  def test_generate_names
    r = Resolv::MDNS.new(:domain => 'local')

    assert_equal(nil,            r.generate_candidates('foo'))
    assert_equal(nil,            r.generate_candidates('foo.'))
    assert_equal(nil,            r.generate_candidates('foo.com'))
    assert_equal(nil,            r.generate_candidates('foo.com.'))
    assert_equal(nil,            r.generate_candidates('foo.local'))
    assert_equal(nil,            r.generate_candidates('foo.local.'))
    assert_equal(nil,            r.generate_candidates('foo.bar.local'))
    assert_equal(nil,            r.generate_candidates('foo.bar.local.'))
    assert_equal(nil,            r.generate_candidates('foo.bar'))
    assert_equal(nil,            r.generate_candidates('foo'))
  end


end

