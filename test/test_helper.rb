ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "minitest/mock"
require "rails/test_help"
require "time"

require_relative "support/auth_helpers"
require_relative "support/role_matrix_helpers"
require_relative "support/openapi_contract_helpers"

class ActiveSupport::TestCase
  # Use the test adapter for Action Cable to avoid external Redis during tests.
  ActionCable.server.config.cable = { adapter: "test" }

  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  setup do
    store = Rack::Attack.cache&.store if defined?(Rack::Attack)
    store&.clear if store.respond_to?(:clear)
  end

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  # Note: You do not have a fixtures directory yet, but this is standard practice.
  # fixtures :all

  # Add more helper methods to be used by all tests here...
  include AuthHelpers
  include RoleMatrixHelpers

  def with_env(vars)
    original = {}
    vars.each do |key, value|
      original[key] = ENV[key]
      ENV[key] = value
    end
    yield
  ensure
    vars.each_key do |key|
      if original[key].nil?
        ENV.delete(key)
      else
        ENV[key] = original[key]
      end
    end
  end
end
