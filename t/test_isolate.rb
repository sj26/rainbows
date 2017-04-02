require 'rubygems'
require 'isolate'
engine = defined?(RUBY_ENGINE) ? RUBY_ENGINE : 'ruby'

path = "tmp/isolate/#{engine}-#{RUBY_VERSION}"
opts = {
  :system => false,
  # we want "ruby-1.8.7" and not "ruby-1.8", so disable multiruby
  :multiruby => false,
  :path => path,
}

old_out = $stdout.dup
$stdout.reopen($stderr)

lock = File.open(__FILE__, "rb")
lock.flock(File::LOCK_EX)
Isolate.now!(opts) do
  gem 'kgio', '2.11.0'
  gem 'rack', '2.0.1'
  gem 'kcar', '0.6.0'
  gem 'raindrops', '0.18.0'
  gem 'unicorn', '5.3.0'

  if engine == "ruby"
    gem 'sendfile', '1.2.2'
    gem 'eventmachine', '1.2.0.1'

    # not compatible with rack 2.x
    # gem 'async_sinatra', '1.2.1'

    if RUBY_VERSION.to_f < 2.2
      gem 'cool.io', '1.1.0'
      gem 'neverblock', '0.1.6.2'
    end
  end

  if defined?(::Fiber) && engine == "ruby"
    if RUBY_VERSION.to_f < 2.2
      gem 'revactor', '0.1.5'
      gem 'rack-fiber_pool', '0.9.2' # depends on EM
    end
  end

  if RUBY_PLATFORM =~ /linux/
    gem 'sleepy_penguin', '3.4.1'

    # is 2.6.32 new enough?
    gem 'io_splice', '4.4.0' if `uname -r`.strip > '2.6.32'
  end
end

$stdout.reopen(old_out)

# don't load the old Rev if it exists, Cool.io 1.0.0 is compatible with it,
# even for everything Revactor uses.
dirs = Dir["#{path}/gems/*-*/lib"]
dirs.delete_if { |x| x =~ %r{/rev-[\d\.]+/lib} }
puts dirs.map { |x| File.expand_path(x) }.join(':')
