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

  test "production resolves host-only session cookie options" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      with_env("SESSION_COOKIE_SAMESITE" => nil, "COOKIE_SAMESITE" => nil, "ALLOW_SAMESITE_NONE" => nil) do
        options = CookieDomainResolver.cookie_options("api.biddersweet.app")
        assert_nil options[:domain]
        assert_equal :lax, options[:same_site]
        assert_equal true, options[:secure]
      end
    end
  end

  test "development keeps cookies host-only" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development")) do
      options = CookieDomainResolver.cookie_options("afterdark.lvh.me")
      assert_nil options[:domain]
    end
  end

  test "same-site none is not allowed for auth cookie hardening" do
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => nil) do
        assert_equal :lax, CookieDomainResolver.same_site
      end

      with_env("SESSION_COOKIE_SAMESITE" => "none", "ALLOW_SAMESITE_NONE" => "true") do
        assert_equal :lax, CookieDomainResolver.same_site
      end
    end
  end

  test "legacy domain resolver supports explicit old-cookie cleanup" do
    assert_equal ".biddersweet.app", CookieDomainResolver.legacy_domain_for("api.biddersweet.app")
    assert_equal ".lvh.me", CookieDomainResolver.legacy_domain_for("afterdark.lvh.me")
    assert_nil CookieDomainResolver.legacy_domain_for("localhost")
  end
end
