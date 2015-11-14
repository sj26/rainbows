# -*- encoding: binary -*-
require "sleepy_penguin"
require "raindrops"

# Like Unicorn itself, this concurrency model is only intended for use
# behind nginx and completely unsupported otherwise.  Even further from
# Unicorn, this isn't even a good idea with normal LAN clients, only nginx!
#
# It does NOT require a thread-safe Rack application at any point, but
# allows streaming data asynchronously via nginx (using the
# "X-Accel-Buffering: no" header to disable buffering).
#
# Unlike Rainbows::Base, this does NOT support persistent
# connections or pipelining.  All \Rainbows! specific configuration
# options are ignored (except Rainbows::Configurator#use).
#
# === RubyGem Requirements
#
# * raindrops 0.6.0 or later
# * sleepy_penguin 3.0.1 or later
module Rainbows::StreamResponseEpoll
  # :stopdoc:
  HEADER_END = "X-Accel-Buffering: no\r\n\r\n"
  autoload :Client, "rainbows/stream_response_epoll/client"

  def http_response_write(socket, status, headers, body)
    hijack = ep_client = false

    if headers
      # don't set extra headers here, this is only intended for
      # consuming by nginx.
      code = status.to_i
      msg = Rack::Utils::HTTP_STATUS_CODES[code]
      buf = "HTTP/1.0 #{msg ? %Q(#{code} #{msg}) : status}\r\n"
      headers.each do |key, value|
        case key
        when "rack.hijack"
          hijack = hijack_prepare(value)
          body = nil # ensure we do not close body
        else
          if /\n/ =~ value
            # avoiding blank, key-only cookies with /\n+/
            buf << value.split(/\n+/).map! { |v| "#{key}: #{v}\r\n" }.join
          else
            buf << "#{key}: #{value}\r\n"
          end
        end
      end
      buf << HEADER_END

      case rv = socket.kgio_trywrite(buf)
      when nil then break
      when String # retry, socket buffer may grow
        buf = rv
      when :wait_writable
        ep_client = Client.new(socket, buf)
        if hijack
          ep_client.hijack(hijack)
        else
          body.each { |chunk| ep_client.write(chunk) }
          ep_client.close
        end
        # body is nil on hijack, in which case ep_client is never closed by us
        return
      end while true
    end

    if hijack
      hijack.call(socket)
      return
    end

    body.each do |chunk|
      if ep_client
        ep_client.write(chunk)
      else
        case rv = socket.kgio_trywrite(chunk)
        when nil then break
        when String # retry, socket buffer may grow
          chunk = rv
        when :wait_writable
          ep_client = Client.new(socket, chunk)
          break
        end while true
      end
    end
  ensure
    return if hijack
    body.respond_to?(:close) and body.close
    if ep_client
      ep_client.close
    else
      socket.shutdown
      socket.close
    end
  end

  # once a client is accepted, it is processed in its entirety here
  # in 3 easy steps: read request, call app, write app response
  def process_client(client)
    status, headers, body = @app.call(env = @request.read(client))

    if 100 == status.to_i
      client.write(Unicorn::Const::EXPECT_100_RESPONSE)
      env.delete(Unicorn::Const::HTTP_EXPECT)
      status, headers, body = @app.call(env)
    end
    @request.headers? or headers = nil
    return if @request.hijacked?
    http_response_write(client, status, headers, body)
  rescue => e
    handle_error(client, e)
  end

  # :startdoc:
end
