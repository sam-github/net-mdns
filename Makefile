# $Id:$

default: test

.PHONY: doc
doc:
	 rdoc -S -o doc net/dns
	 open doc/index.html &

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

ri:
	rdoc18 -f ri net/dns/mdns.rb

open:
	open doc/index.html

V=0.0
P=mdns-$V
R=releases/$P

release: doc pkg

install:
	for r in /usr/bin/ruby /opt/local/bin/ruby ruby18; do (cd $R; sudo $$r setup.rb); done

pkg:
	rm -rf $R/
	mkdir -p releases
	mkdir -p $R/samples
	mkdir -p $R/lib/net/dns
	cp setup.rb $R/
	cp net/dns/*.rb        $R/lib/net/dns/
	cp mdns.rb             $R/samples
	cp mdns_demo.rb        $R/samples
	cd releases && tar -zcf $P.tgz $P

