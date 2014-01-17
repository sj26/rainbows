# -*- encoding: binary -*-

# base class for \Rainbows! concurrency models, this is currently used by
# ThreadSpawn and ThreadPool models.  Base is also its own
# (non-)concurrency model which is basically Unicorn-with-keepalive, and
# not intended for production use, as keepalive with a pure prefork
# concurrency model is extremely expensive.
module Rainbows::Base
  # :stopdoc:

  def sig_receiver(worker)
    begin
      worker.to_io.kgio_wait_readable
      worker.kgio_tryaccept # Unicorn::Worker#kgio_tryaccept
    rescue => e
      Rainbows.alive or return
      Unicorn.log_error(Rainbows.server.logger, "signal receiver", e)
    end while true
  end

  # this method is called by all current concurrency models
  def init_worker_process(worker) # :nodoc:
    readers = super(worker)
    Rainbows::Response.setup
    Rainbows::MaxBody.setup
    Rainbows.worker = worker

    # spawn Threads since Logger takes a mutex by default and
    # we can't safely lock a mutex in a signal handler
    trap(:USR1) { Thread.new { reopen_worker_logs(worker.nr) } }
    trap(:QUIT) { Thread.new { Rainbows.quit! } }
    [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
    Rainbows::ProcessClient.const_set(:APP, Rainbows.server.app)
    Thread.new { sig_receiver(worker) }
    logger.info "Rainbows! #@use worker_connections=#@worker_connections"
    Rainbows.readers = readers # for Rainbows.quit
    readers # unicorn 4.8+ needs this
  end

  def process_client(client)
    client.process_loop
  end

  def self.included(klass) # :nodoc:
    klass.const_set :LISTENERS, Rainbows::HttpServer::LISTENERS
  end

  def reopen_worker_logs(worker_nr)
    logger.info "worker=#{worker_nr} reopening logs..."
    Unicorn::Util.reopen_logs
    logger.info "worker=#{worker_nr} done reopening logs"
    rescue
      Rainbows.quit! # let the master reopen and refork us
  end
  # :startdoc:
end
