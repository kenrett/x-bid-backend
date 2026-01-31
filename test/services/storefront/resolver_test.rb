require "test_helper"

class StorefrontResolverTest < ActiveSupport::TestCase
  class RequestStub
    attr_reader :headers, :host, :fullpath, :request_id

    def initialize(headers: {}, host: nil, fullpath: "/test", request_id: "req-1", http_host: nil)
      @headers = headers
      @host = host
      @fullpath = fullpath
      @request_id = request_id
      @http_host = http_host
    end

    def get_header(name)
      return @http_host if name == "HTTP_HOST"

      nil
    end
  end

  test "valid header overrides host inference" do
    request = RequestStub.new(
      headers: { "X-Storefront-Key" => " AfterDark " },
      host: "marketplace.biddersweet.app"
    )

    assert_equal "afterdark", Storefront::Resolver.resolve(request)
  end

  test "invalid header falls back to host and logs warning" do
    logs = []
    request = RequestStub.new(
      headers: { "X-Storefront-Key" => "not-a-storefront" },
      host: "marketplace.biddersweet.app"
    )

    AppLogger.stub(:log, ->(event:, **context) { logs << [ event, context ]; nil }) do
      assert_equal "marketplace", Storefront::Resolver.resolve(request)
    end

    assert logs.any? { |event, context|
      event == "storefront.resolve.invalid_header_key" &&
        context[:invalid_key] == "not-a-storefront" &&
        context[:resolved_to] == "marketplace"
    }
  end

  test "host inference detects afterdark and marketplace" do
    afterdark_request = RequestStub.new(host: "afterdark.biddersweet.app")
    marketplace_request = RequestStub.new(host: "marketplace.biddersweet.app")
    main_request = RequestStub.new(host: "www.biddersweet.app")

    assert_equal "afterdark", Storefront::Resolver.resolve(afterdark_request)
    assert_equal "marketplace", Storefront::Resolver.resolve(marketplace_request)
    assert_equal "main", Storefront::Resolver.resolve(main_request)
  end

  test "missing header and host defaults to main without raising" do
    request = RequestStub.new(host: nil, http_host: nil)

    assert_equal "main", Storefront::Resolver.resolve(request)
  end
end
