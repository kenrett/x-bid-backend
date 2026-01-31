require "test_helper"

class StorefrontContextTestController < ActionController::API
  def show
    render plain: Current.storefront_key.to_s
  end
end

class StorefrontContextTest < ActionDispatch::IntegrationTest
  test "default storefront_key is main" do
    assert_equal "main", storefront_key_for
  end

  test "host mapping resolves storefront_key" do
    assert_equal "main", storefront_key_for(host: "biddersweet.app")
    assert_equal "main", storefront_key_for(host: "www.biddersweet.app")
    assert_equal "afterdark", storefront_key_for(host: "afterdark.biddersweet.app")
    assert_equal "marketplace", storefront_key_for(host: "marketplace.biddersweet.app")
  end

  test "header X-Storefront-Key overrides host mapping" do
    assert_equal "marketplace",
                 storefront_key_for(
                   host: "afterdark.biddersweet.app",
                   headers: { "X-Storefront-Key" => "marketplace" }
                 )
  end

  test "invalid header defaults to main and logs a warning" do
    warnings = []
    AppLogger.stub(:log, ->(event:, **context) { warnings << [ event, context ]; nil }) do
    assert_equal "afterdark",
                   storefront_key_for(
                     host: "afterdark.biddersweet.app",
                     headers: { "X-Storefront-Key" => "not-a-storefront" }
                   )
    end

    assert warnings.any? { |event, _| event == "storefront.resolve.invalid_header_key" }
  end

  private

  def storefront_key_for(host: nil, headers: {})
    with_routing do |set|
      set.draw do
        get "/__test/storefront", to: "storefront_context_test#show"
      end

      host!(host) if host
      get "/__test/storefront", headers: headers
      assert_response :success
      response.body.to_s
    end
  end
end
