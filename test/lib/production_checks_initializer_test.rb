require "test_helper"

class ProductionChecksInitializerTest < ActiveSupport::TestCase
  INITIALIZER_PATH = Rails.root.join("config/initializers/production_checks.rb")
  REQUIRED_ENV_MESSAGES = {
    "SECRET_KEY_BASE" => "SECRET_KEY_BASE environment variable is missing. Application cannot start.",
    "DATABASE_URL" => "DATABASE_URL environment variable is missing. Application cannot start.",
    "REDIS_URL" => "REDIS_URL environment variable is missing. Application cannot start."
  }.freeze

  test "raises in production when a required env var is missing" do
    REQUIRED_ENV_MESSAGES.each do |missing_key, expected_message|
      logger = Minitest::Mock.new
      logger.expect(:fatal, nil, [ expected_message ])

      with_env(
        "SECRET_KEY_BASE" => "secret",
        "DATABASE_URL" => "postgres://example",
        "REDIS_URL" => "redis://example",
        missing_key => nil
      ) do
        error = assert_raises(RuntimeError) do
          Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
            Rails.stub(:logger, logger) do
              load INITIALIZER_PATH
            end
          end
        end

        assert_equal expected_message, error.message
      end

      logger.verify
    end
  end

  test "does not raise in production when required env vars are present" do
    with_env(
      "SECRET_KEY_BASE" => "secret",
      "DATABASE_URL" => "postgres://example",
      "REDIS_URL" => "redis://example"
    ) do
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
        load INITIALIZER_PATH
      end
    end

    assert true
  end

  test "does not raise outside production" do
    with_env("SECRET_KEY_BASE" => nil, "DATABASE_URL" => nil, "REDIS_URL" => nil) do
      Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
        load INITIALIZER_PATH
      end
    end

    assert true
  end
end
