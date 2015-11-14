# -*- encoding: binary -*-
# :enddoc:
require 'tempfile'
module Rainbows::ReverseProxy::EvClient
  include Rainbows::ReverseProxy::Synchronous
  CBB = Unicorn::TeeInput.client_body_buffer_size

  def receive_data(buf)
    if @body
      @body << buf
    else
      response = @parser.headers(@headers, @rbuf << buf) or return
      if (cl = @headers['Content-Length'.freeze] && cl.to_i > CBB) ||
         (%r{\bchunked\b} =~ @headers['Transfer-Encoding'.freeze])
        @body = LargeBody.new("")
        @body << @rbuf
        @response = response << @body
      else
        @body = @rbuf.dup
        @response = response << [ @body ]
      end
    end
  end

  class LargeBody < Tempfile
    def each
      buf = ""
      rewind
      while read(16384, buf)
        yield buf
      end
    end

    alias close close!
  end
end
