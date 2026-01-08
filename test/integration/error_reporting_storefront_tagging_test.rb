require "test_helper"

class ErrorReportingStorefrontTaggingTestController < ActionController::API
  def index
    head :no_content
  end
end

class ErrorReportingStorefrontTaggingTest < ActionDispatch::IntegrationTest
  test "request storefront_key is attached to error reporter context when available" do
    $__test_sentry_tags__ = []

    sentry = Module.new do
      def self.configure_scope
        scope = Object.new
        scope.define_singleton_method(:set_tags) do |hash|
          $__test_sentry_tags__ << hash
        end
        yield scope
      end
    end

    Object.const_set(:Sentry, sentry)

    with_routing do |set|
      set.draw do
        get "/__test/error_reporting", to: "error_reporting_storefront_tagging_test#index"
      end

      host!("afterdark.biddersweet.app")
      get "/__test/error_reporting"
      assert_response :no_content
    end

    assert $__test_sentry_tags__.any? { |h| h.is_a?(Hash) && h[:storefront_key] == "afterdark" }
  ensure
    Object.send(:remove_const, :Sentry) if Object.const_defined?(:Sentry)
    $__test_sentry_tags__ = nil
  end
end
