# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
min_threads = ENV.fetch("RAILS_MIN_THREADS", 2).to_i
max_threads = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads min_threads, max_threads

# Keep production on a single Puma process by default for low-memory instances
# (e.g., Render 512MB). Set WEB_CONCURRENCY > 0 only when there is headroom.
workers_count = ENV.fetch("WEB_CONCURRENCY", 0).to_i
workers workers_count if workers_count.positive?

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run Solid Queue inside Puma only when explicitly requested and not on web role.
# Prefer a dedicated worker process (`bin/jobs` or `bin/rails solid_queue:start`).
process_role = ENV.fetch("PROCESS_ROLE", "web")
run_solid_queue_in_puma =
  ENV["SOLID_QUEUE_IN_PUMA"].to_s.casecmp("true").zero? && process_role != "web"
plugin :solid_queue if run_solid_queue_in_puma

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
