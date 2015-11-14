# -*- encoding: binary -*-
# :enddoc:
# avoid modifying Unicorn::HttpParser
class Rainbows::HttpParser < Unicorn::HttpParser
  @keepalive_requests = 100
  class << self
    attr_accessor :keepalive_requests
  end

  def initialize(*args)
    @keepalive_requests = self.class.keepalive_requests
    super
  end

  def next?
    return false if (@keepalive_requests -= 1) <= 0
    super
  end

  def hijack_setup(io)
    @hijack_io = io
    env['rack.hijack'] = self # avoid allocating a new proc this way
  end

  def call # for rack.hijack
    env['rack.hijack_io'] = @hijack_io
  end

  def self.quit
    alias_method :next?, :never!
  end

  def never!
    false
  end
end
