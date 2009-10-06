# we can run tests in parallel with GNU make

all::

ruby = ruby
rainbows_lib := $(shell cd ../lib && pwd)
-include ../local.mk
ifeq ($(RUBY_VERSION),)
  RUBY_VERSION := $(shell $(ruby) -e 'puts RUBY_VERSION')
endif

ifeq ($(RUBYLIB),)
  RUBYLIB := $(rainbows_lib)
else
  RUBYLIB := $(rainbows_lib):$(RUBYLIB)
endif
export RUBYLIB

T = $(wildcard t[0-9][0-9][0-9][0-9]-*.sh)

all:: $(T)

# can't rely on "set -o pipefail" since we don't require bash or ksh93 :<
t_code = $@-$(RUBY_VERSION).code
t_log = $@-$(RUBY_VERSION).log
t_run = $(TRACER) $(SHELL) $(TEST_OPTS) $@

# prefix stdout messages with ':', and stderr messages with '!'
t_wrap = ( ( ( $(RM) $(t_code); \
  $(t_run); \
  echo $$? > $(t_code) ) \
  | sed 's/^/$(pfx):/' 1>&3 ) 2>&1 \
  | sed 's/^/$(pfx)!/' 1>&2 ) 3>&1

ifndef V
  quiet_pre = @echo '* $@';
  quiet_post = > $(t_log) 2>&1; exit $$(cat $(t_code))
  pfx =
else
  ifeq ($(V),2)
    TEST_OPTS += -x
  endif
  quiet_pre = @echo '* $@';
  quiet_post = 2>&1 | tee $(t_log); exit $$(cat $(t_code))
  pfx = $@
endif

# TRACER='strace -f -o $@.strace -s 100000'
run_test = $(quiet_pre) ( $(t_wrap) ) $(quiet_post)

test-bin-$(RUBY_VERSION)/rainbows: ruby_bin = $(shell which $(ruby))
test-bin-$(RUBY_VERSION)/rainbows: ../bin/rainbows
	mkdir -p $(@D)
	install -m 755 $^ $@+
	$(ruby) -i -p -e '$$_.gsub!(%r{^#!.*$$},"#!$(ruby_bin)")' $@+
	cmp $@+ $@ 2>/dev/null || mv $@+ $@
	$(RM) $@+

$(T): export ruby := $(ruby)
$(T): export PATH := $(CURDIR)/test-bin-$(RUBY_VERSION):$(PATH)
$(T): test-bin-$(RUBY_VERSION)/rainbows
	$(run_test)

clean:
	$(RM) -r *.log *.code test-bin-$(RUBY_VERSION)

.PHONY: $(T) clean