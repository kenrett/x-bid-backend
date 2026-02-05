require "test_helper"

class CookieDomainResolverTest < ActiveSupport::TestCase
  def with_env(vars)
    original = {}
    vars.each do |key, value|
      original[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  test "production resolves biddersweet domain and secure cookies" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      with_env("SESSION_COOKIE_SAMESITE" => nil, "COOKIE_SAMESITE" => nil, "ALLOW_SAMESITE_NONE" => nil) do
        options = CookieDomainResolver.cookie_options("api.biddersweet.app")
        assert_equal ".biddersweet.app", options[:domain]
        assert_equal :lax, options[:same_site]
        assert_equal true, options[:secure]
      end
    end
  end

  test "development resolves lvh.me domain" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      options = CookieDomainResolver.cookie_options("afterdark.lvh.me")
      assert_equal ".lvh.me", options[:domain]
    end
  end

  test "same-site none requires explicit allow flag" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => nil) do
        assert_equal :lax, CookieDomainResolver.same_site
      end

      with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => "true") do
        assert_equal :none, CookieDomainResolver.same_site
        assert_equal true, CookieDomainResolver.secure?(:none)
      end
    end
  end

  test "session cookie domain override is scoped to matching hosts" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      with_env("SESSION_COOKIE_DOMAIN" => ".example.com") do
        assert_equal ".example.com", CookieDomainResolver.domain_for("api.example.com")
        assert_equal ".biddersweet.app", CookieDomainResolver.domain_for("api.biddersweet.app")
      end
    end
  end
end
