require "test_helper"

class FrontendOriginsTest < ActiveSupport::TestCase
  test "falls back to localhost origin in test env when credentials missing" do
    creds = Object.new
    assert_equal [
      "http://localhost:5173",
      "http://afterdark.localhost:5173",
      "http://marketplace.localhost:5173",
      "http://account.localhost:5173",
      "http://lvh.me:5173"
    ], FrontendOrigins.for_env!("test", credentials: creds)
  end

  test "uses FRONTEND_ORIGINS env var when present" do
    creds = Object.new
    ENV["FRONTEND_ORIGINS"] = "https://a.example, https://b.example/"
    assert_equal [ "https://a.example", "https://b.example" ], FrontendOrigins.for_env!("production", credentials: creds)
  ensure
    ENV.delete("FRONTEND_ORIGINS")
  end

  test "matches biddersweet www and subdomains but rejects lookalikes" do
    creds = Struct.new(:frontend_origins).new({ "production" => [ "https://biddersweet.app" ] })

    assert FrontendOrigins.allowed_origin?("https://www.biddersweet.app", env: "production", credentials: creds)
    assert FrontendOrigins.allowed_origin?("https://random-subdomain.biddersweet.app", env: "production", credentials: creds)
    refute FrontendOrigins.allowed_origin?("https://biddersweet.app.evil.com", env: "production", credentials: creds)
  end
end
