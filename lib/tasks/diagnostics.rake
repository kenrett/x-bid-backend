# Usage: bin/rails diagnostics:env
#
# This task prints safe environment diagnostics to STDOUT.
# It is designed to be run in production to verify the environment configuration
# without leaking secrets (like database passwords) into the logs.
namespace :diagnostics do
  desc "Print safe environment diagnostics (no secrets)."
  task env: :environment do
    puts "Rails.env: #{Rails.env}"
    puts "DATABASE_URL present?: #{ENV.key?("DATABASE_URL") && ENV["DATABASE_URL"].to_s.strip != ""}"

    begin
      adapter = ActiveRecord::Base.connection_db_config.adapter
      puts "DB adapter (ActiveRecord): #{adapter}"
    rescue => e
      puts "DB adapter (ActiveRecord): unavailable (#{e.class})"
    end
  end
end
