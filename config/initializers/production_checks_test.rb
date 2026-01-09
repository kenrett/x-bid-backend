require "test_helper"

class ProductionChecksTest < ActiveSupport::TestCase
  test "raises if DATABASE_URL is missing in production" do
    original_db_url = ENV["DATABASE_URL"]

    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      ENV.delete("DATABASE_URL")

      error = assert_raises(RuntimeError) do
        load Rails.root.join("config/initializers/production_checks.rb")
      end

      assert_equal "DATABASE_URL environment variable is missing. Application cannot start.", error.message
    end
  ensure
    if original_db_url
      ENV["DATABASE_URL"] = original_db_url
    else
      ENV.delete("DATABASE_URL")
    end
  end
end
