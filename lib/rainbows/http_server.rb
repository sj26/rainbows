# -*- encoding: binary -*-
# :enddoc:

class Rainbows::HttpServer < Unicorn::HttpServer
  def self.setup(block)
    Rainbows.server.instance_eval(&block)
  end

  def initialize(app, options)
    Rainbows.server = self
    @logger = Unicorn::Configurator::DEFAULTS[:logger]
    super(app, options)
    defined?(@use) or use(:Base)
    @worker_connections ||= @use == :Base ? 1 : 50
  end

  def reopen_worker_logs(worker_nr)
    logger.info "worker=#{worker_nr} reopening logs..."
    Unicorn::Util.reopen_logs
    logger.info "worker=#{worker_nr} done reopening logs"
    rescue
      Rainbows.quit! # let the master reopen and refork us
  end

  # Add one second to the timeout since our fchmod heartbeat is less
  # precise (and must be more conservative) than Unicorn does.  We
  # handle many clients per process and can't chmod on every
  # connection we accept without wasting cycles.  That added to the
  # fact that we let clients keep idle connections open for long
  # periods of time means we have to chmod at a fixed interval.
  def timeout=(nr)
    @timeout = nr + 1
  end

  def load_config!
    use :Base
    Rainbows.defaults!
    @worker_connections = nil
    super
    @worker_connections ||= @use == :Base ? 1 : 50
  end

  def worker_loop(worker)
    orig = method(:worker_loop)
    extend(Rainbows.const_get(@use))
    m = method(:worker_loop)
    orig == m ? super(worker) : worker_loop(worker)
  end

  def spawn_missing_workers
    # 5: std{in,out,err} + heartbeat FD + per-process listener
    nofile = 5 + @worker_connections + LISTENERS.size
    trysetrlimit(:RLIMIT_NOFILE, nofile)

    case @use
    when :ThreadSpawn, :ThreadPool, :ActorSpawn,
         :CoolioThreadSpawn, :RevThreadSpawn,
         :WriterThreadPool, :WriterThreadSpawn
      trysetrlimit(:RLIMIT_NPROC, @worker_connections + LISTENERS.size + 1)
    end
    super
  end

  def trysetrlimit(resource, want)
    var = Process.const_get(resource)
    cur, max = Process.getrlimit(var)
    cur <= want and Process.setrlimit(var, cur = max > want ? max : want)
    if cur == want
      @logger.warn "#{resource} rlim_cur=#{cur} is barely enough"
      @logger.warn "#{svc} may monopolize resources dictated by #{resource}" \
                   " and leave none for your app"
    end
    rescue => e
      @logger.error e.message
      @logger.error "#{resource} needs to be increased to >=#{want} before" \
                    " starting #{svc}"
  end

  def svc
    File.basename($0)
  end

  def use(*args)
    model = args.shift or return @use
    mod = begin
      Rainbows.const_get(model)
    rescue NameError => e
      logger.error "error loading #{model.inspect}: #{e}"
      e.backtrace.each { |l| logger.error l }
      raise ArgumentError, "concurrency model #{model.inspect} not supported"
    end

    Module === mod or
      raise ArgumentError, "concurrency model #{model.inspect} not supported"
    args.each do |opt|
      case opt
      when Hash; Rainbows::O.update(opt)
      when Symbol; Rainbows::O[opt] = true
      else; raise ArgumentError, "can't handle option: #{opt.inspect}"
      end
    end
    mod.setup if mod.respond_to?(:setup)
    new_defaults = {
      'rainbows.model' => (@use = model.to_sym),
      'rack.multithread' => !!(model.to_s =~ /Thread/),
      'rainbows.autochunk' => [:Coolio,:Rev,:Epoll,:XEpoll,
                               :EventMachine,:NeverBlock].include?(@use),
    }
    Rainbows::Const::RACK_DEFAULTS.update(new_defaults)
  end

  def worker_connections(*args)
    return @worker_connections if args.empty?
    nr = args[0]
    (Integer === nr && nr > 0) or
      raise ArgumentError, "worker_connections must be a positive Integer"
    @worker_connections = nr
  end

  def keepalive_timeout(nr)
    (Integer === nr && nr >= 0) or
      raise ArgumentError, "keepalive_timeout must be a non-negative Integer"
    Rainbows.keepalive_timeout = nr
  end

  def keepalive_requests(nr)
    Integer === nr or
      raise ArgumentError, "keepalive_requests must be a non-negative Integer"
    Unicorn::HttpRequest.keepalive_requests = nr
  end

  def client_max_body_size(nr)
    err = "client_max_body_size must be nil or a non-negative Integer"
    case nr
    when nil
    when Integer
      nr >= 0 or raise ArgumentError, err
    else
      raise ArgumentError, err
    end
    Rainbows.client_max_body_size = nr
  end

  def client_header_buffer_size(bytes)
    Integer === bytes && bytes > 0 or raise ArgumentError,
            "client_header_buffer_size must be a positive Integer"
    Rainbows.client_header_buffer_size = bytes
  end
end
