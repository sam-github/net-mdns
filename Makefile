# $Id:$

default:
	ruby18 -c net/dns/v2mdns.rb

.PHONY: doc
doc:
	 rdoc18 -S -o doc net/dns/*.rb
	 open doc/index.html &
	 cp TODO doc/TODO
	 cp mdns.rb doc/mdns.txt
	 cp v1mdns.rb doc/v1mdns.txt
	 cp v1demo.rb doc/v1demo.txt

doc-upload:
	cd doc; scp -r . sam@rubyforge.org:/var/www/gforge-projects/dnssd/net-mdns

submit: release doc-upload

.PHONY: tags
tags:
	exctags -R $(TAGSRC)
	RUBYLIB=/Users/sam/p/ruby/ruby/lib rdoc18 -f tags net/dns/*.rb
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

