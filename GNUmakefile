# use GNU Make to run tests in parallel, and without depending on RubyGems
all::
RSYNC_DEST := yhbt.net:/srv/yhbt/rainbows
rfpackage := rainbows
PLACEHOLDERS := rainbows_1 Summary

Documentation/comparison.html: Documentation/comparison.haml
	haml < $< >$@+ && mv $@+ $@

# only for the website
doc :: Documentation/comparison.html
doc :: man/man1/rainbows.1.html

include pkg.mk
man1 := man/man1/rainbows.1

clean:
	-$(MAKE) -C Documentation clean
	$(RM) $(man1) $(html1)

pkg_extra += $(man1) lib/rainbows/version.rb

%.1.html: %.1
	$(OLDDOC) man2html -o $@ $<

lib/rainbows/version.rb: GIT-VERSION-FILE

all:: test
test: lib/rainbows/version.rb
	$(MAKE) -C t
