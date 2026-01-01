require "test_helper"

class AppLoggerTest < ActiveSupport::TestCase
  test "AppLogger includes Current context in JSON payload" do
    Current.request_id = "req-123"
    Current.user_id = 42
    Current.session_token_id = 99

    messages = []
    Rails.logger.stub(:info, ->(msg) { messages << msg }) do
      AppLogger.log(event: "test.event", foo: "bar")
    end

    payload = JSON.parse(messages.fetch(0))
    assert_equal "test.event", payload.fetch("event")
    assert_equal "req-123", payload.fetch("request_id")
    assert_equal 42, payload.fetch("user_id")
    assert_equal 99, payload.fetch("session_token_id")
    assert_equal "bar", payload.fetch("foo")
  ensure
    Current.reset
  end

  test "explicit context overrides Current context" do
    Current.user_id = 1

    messages = []
    Rails.logger.stub(:info, ->(msg) { messages << msg }) do
      AppLogger.log(event: "test.event", user_id: 2)
    end

    payload = JSON.parse(messages.fetch(0))
    assert_equal 2, payload.fetch("user_id")
  ensure
    Current.reset
  end
end
