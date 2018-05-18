use Rack::Lint
use Rack::ContentLength
use Rack::ContentType, "text/plain"
class DieIfUsed
  def each
    abort "body.each called after response hijack\n"
  end

  def close
    abort "body.close called after response hijack\n"
  end
end
def lazy_close(io)
  thr = Thread.new do
    # wait and see if Rainbows! accidentally closes us
    sleep((ENV["DELAY"] || 10).to_i)
    begin
      io.close
    rescue => e
      warn "E: #{e.message} (#{e.class})"
      exit!(3)
    end
  end
  at_exit { thr.join }
end

run lambda { |env|
  case env["PATH_INFO"]
  when "/hijack_req"
    if env["rack.hijack?"]
      io = env["rack.hijack"].call
      if io.respond_to?(:read_nonblock) &&
         env["rack.hijack_io"].respond_to?(:read_nonblock)

        # exercise both, since we Rack::Lint may use different objects
        env["rack.hijack_io"].write("HTTP/1.0 200 OK\r\n\r\n")
        io.write("request.hijacked")
        lazy_close(io)
        return [ 500, {}, DieIfUsed.new ]
      end
    end
    [ 500, {}, [ "hijack BAD\n" ] ]
  when "/hijack_res"
    r = "response.hijacked"
    [ 200,
      {
        "Content-Length" => r.bytesize.to_s,
        "rack.hijack" => proc do |sock|
          io.write(r)
          lazy_close(sock)
        end
      },
      DieIfUsed.new
    ]
  end
}
