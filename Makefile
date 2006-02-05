# $Id:$

default:
	ruby18 -c net/dns/mdns.rb

SAMPLES=mdns.rb exhttp.rb exhttpv1.rb v1mdns.rb v1demo.rb mdns-watch.rb exwebrick.rb

.PHONY: doc
doc:
	 rdoc18 -S -o doc net
	 cp TODO doc/TODO
	 for s in $(SAMPLES); do cp $$s doc/`basename $$s .rb`.txt; done
	 chmod u=rw doc/*.txt
	 chmod go=r doc/*.txt
	 open doc/index.html

doc-upload:
	cd doc; scp -r . sam@rubyforge.org:/var/www/gforge-projects/dnssd/net-mdns/

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

diff:
	diff -u ../ruby/lib/resolv.rb net/dns/resolv.rb
	diff -u ../ruby/lib/resolv-replace.rb net/dns/resolv-replace.rb


ri:
	rdoc18 -f ri net/dns/mdns.rb

open:
	open doc/index.html

V=0.3
P=net-mdns-$V
R=releases/$P

release: stamp doc pkg

install:
	for r in /usr/bin/ruby /opt/local/bin/ruby ruby18; do (cd $R; $$r setup.rb config; $$r setup.rb setup; echo sudo $$r setup.rb install); done

stamp:
	ruby -pi~ -e '$$_.gsub!(/ 0\.\d+(bis|[a-z])?/, " $V")' net/dns/mdns.rb

pkg:
	rm -rf                 $R/
	mkdir -p               releases
	mkdir -p               $R/samples
	mkdir -p               $R/lib/net/dns
	cp setup.rb            $R/
	cp COPYING README TODO $R/
	cp net/dns/*.rb        $R/lib/net/dns/
	cp net/*.rb            $R/lib/net/
	cp $(SAMPLES)          $R/samples
	cp test_dns.rb         $R/samples
	cd releases && tar -zcf $P.tgz $P

