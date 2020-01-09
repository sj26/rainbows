# use GNU Make to run tests in parallel, and without depending on RubyGems
all::
RSYNC_DEST := yhbt.net:/srv/yhbt/rainbows
rfpackage := rainbows
PLACEHOLDERS := rainbows_1 Summary

man-rdoc: man html
	$(MAKE) -C Documentation comparison.html
doc:: man-rdoc
include pkg.mk

base_bins := rainbows
bins := $(addprefix bin/, $(base_bins))
man1_bins := $(addsuffix .1, $(base_bins))
man1_paths := $(addprefix man/man1/, $(man1_bins))

clean:
	-$(MAKE) -C Documentation clean

man html:
	$(MAKE) -C Documentation install-$@

pkg_extra += $(man1_paths) lib/rainbows/version.rb

lib/rainbows/version.rb: GIT-VERSION-FILE

all:: test
test: lib/rainbows/version.rb
	$(MAKE) -C t

.PHONY: man html
