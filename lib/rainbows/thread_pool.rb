# -*- encoding: binary -*-

module Rainbows

  # Implements a worker thread pool model.  This is suited for platforms
  # like Ruby 1.9, where the cost of dynamically spawning a new thread
  # for every new client connection is higher than with the ThreadSpawn
  # model.
  #
  # This model should provide a high level of compatibility with all
  # Ruby implementations, and most libraries and applications.
  # Applications running under this model should be thread-safe
  # but not necessarily reentrant.
  #
  # Applications using this model are required to be thread-safe.
  # Threads are never spawned dynamically under this model.  If you're
  # connecting to external services and need to perform DNS lookups,
  # consider using the "resolv-replace" library which replaces parts of
  # the core Socket package with concurrent DNS lookup capabilities.
  #
  # This model probably less suited for many slow clients than the
  # others and thus a lower +worker_connections+ setting is recommended.

  module ThreadPool

    include Base

    def worker_loop(worker)
      init_worker_process(worker)
      pool = (1..worker_connections).map { new_worker_thread }

      while G.alive
        # if any worker dies, something is serious wrong, bail
        pool.each do |thr|
          G.tick
          thr.join(1) and G.quit!
        end
      end
      join_threads(pool)
    end

    def new_worker_thread
      Thread.new {
        begin
          begin
            # TODO: check if select() or accept() is a problem on large
            # SMP systems under Ruby 1.9.  Hundreds of native threads
            # all working off the same socket could be a thundering herd
            # problem.  On the other hand, a thundering herd may not
            # even incur as much overhead as an extra Mutex#synchronize
            ret = IO.select(LISTENERS, nil, nil, 1) and
                  ret.first.each do |sock|
                    begin
                      process_client(sock.accept_nonblock)
                    rescue Errno::EAGAIN, Errno::ECONNABORTED
                    end
                  end
          rescue Errno::EINTR
          rescue Errno::EBADF, TypeError
            break
          end
        rescue Object => e
          listen_loop_error(e)
        end while G.alive
      }
    end

  end
end
