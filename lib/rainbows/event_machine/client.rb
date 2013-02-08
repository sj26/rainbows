# -*- encoding: binary -*-
# :enddoc:
class Rainbows::EventMachine::Client < EM::Connection
  include Rainbows::EvCore
  Rainbows.config!(self, :keepalive_timeout)

  def initialize(io)
    @_io = io
    @deferred = nil
  end

  alias write send_data
  alias hijacked detach

  def receive_data(data)
    # To avoid clobbering the current streaming response
    # (often a static file), we do not attempt to process another
    # request on the same connection until the first is complete
    if @deferred
      if data
        @buf << data
        @_io.shutdown(Socket::SHUT_RD) if @buf.size > 0x1c000
      end
      EM.next_tick { receive_data(nil) } unless @buf.empty?
    else
      on_read(data || Z) if (@buf.size > 0) || data
    end
  end

  def quit
    super
    close_connection_after_writing if nil == @deferred
  end

  def app_call input
    set_comm_inactivity_timeout 0
    @env[RACK_INPUT] = input
    @env[REMOTE_ADDR] = @_io.kgio_addr
    @env[ASYNC_CALLBACK] = method(:write_async_response)
    @env[ASYNC_CLOSE] = EM::DefaultDeferrable.new
    @hp.hijack_setup(@env, @_io)
    status, headers, body = catch(:async) {
      APP.call(@env.merge!(RACK_DEFAULTS))
    }
    return hijacked if @hp.hijacked?

    if (nil == status || -1 == status)
      @deferred = true
    else
      ev_write_response(status, headers, body, @hp.next?)
    end
  end

  def deferred_errback(orig_body)
    @deferred.errback do
      orig_body.close if orig_body.respond_to?(:close)
      @deferred = nil
      quit
    end
  end

  def deferred_callback(orig_body, alive)
    @deferred.callback do
      orig_body.close if orig_body.respond_to?(:close)
      @deferred = nil
      alive ? receive_data(nil) : quit
    end
  end

  def ev_write_response(status, headers, body, alive)
    @state = :headers if alive
    if body.respond_to?(:errback) && body.respond_to?(:callback)
      write_headers(status, headers, alive, body) or return hijacked
      @deferred = body
      write_body_each(body)
      deferred_errback(body)
      deferred_callback(body, alive)
      return
    elsif body.respond_to?(:to_path)
      st = File.stat(path = body.to_path)

      if st.file?
        write_headers(status, headers, alive, body) or return hijacked
        @deferred = stream_file_data(path)
        deferred_errback(body)
        deferred_callback(body, alive)
        return
      elsif st.socket? || st.pipe?
        chunk = stream_response_headers(status, headers, alive, body)
        return hijacked if nil == chunk
        io = body_to_io(@deferred = body)
        m = chunk ? Rainbows::EventMachine::ResponseChunkPipe :
                    Rainbows::EventMachine::ResponsePipe
        return EM.watch(io, m, self).notify_readable = true
      end
      # char or block device... WTF? fall through to body.each
    end
    write_response(status, headers, body, alive) or return hijacked
    if alive
      if @deferred.nil?
        if @buf.empty?
          set_comm_inactivity_timeout(KEEPALIVE_TIMEOUT)
        else
          EM.next_tick { receive_data(nil) }
        end
      end
    else
      quit unless @deferred
    end
  end

  def next!
    @deferred.close if @deferred.respond_to?(:close)
    @deferred = nil
    @hp.keepalive? ? receive_data(nil) : quit
  end

  def unbind
    return if @hp.hijacked?
    async_close = @env[ASYNC_CLOSE] and async_close.succeed
    @deferred.respond_to?(:fail) and @deferred.fail
    begin
      @_io.close
    rescue Errno::EBADF
      # EventMachine's EventableDescriptor::Close() may close
      # the underlying file descriptor without invalidating the
      # associated IO object on errors, so @_io.closed? isn't
      # sufficient.
    end
  end
end
