require "test_helper"

class RoutesTest < ActionDispatch::IntegrationTest
  test "account data export routes" do
    assert_routing(
      { method: "get", path: "/api/v1/account/data/export" },
      { controller: "api/v1/account_exports", action: "show" }
    )
    assert_routing(
      { method: "post", path: "/api/v1/account/data/export" },
      { controller: "api/v1/account_exports", action: "create" }
    )
  end

  test "account export download route remains available" do
    assert_routing(
      { method: "get", path: "/api/v1/account/export/download" },
      { controller: "api/v1/account_exports", action: "download" }
    )
  end

  test "legacy account export routes are removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/api/v1/account/export",
        method: :get
      )
    end

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/api/v1/account/export",
        method: :post
      )
    end
  end
end
