# $Id:$

default: test

.PHONY: doc
doc:
	 rdoc -S -o doc net/dns

.PHONY: tags
tags:
	exctags -R multicast.rb
	RUBYLIB=/Users/sam/p/ruby/ruby/lib rdoc18 -f tags multicast.rb
	mv tags tags.ctags
	sort tags.ctags tags.rdoc > tags

test:
	#/usr/bin/ruby -w -r 1.6-resolv.rb rr.rb
	#/opt/local/bin/ruby -w -r 1.8-resolv.rb rr.rb
	/usr/local/bin/ruby18 -w rr.rb

bug:
	/usr/local/bin/ruby18 -w -r 1.8-resolv.rb bug.rb

