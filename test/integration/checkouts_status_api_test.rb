require "test_helper"
require "ostruct"

class CheckoutsStatusApiTest < ActionDispatch::IntegrationTest
  test "owner can query checkout session status" do
    owner = create_actor(role: :user)

    checkout_session = OpenStruct.new(
      payment_status: "paid",
      status: "complete",
      customer_email: owner.email_address,
      metadata: OpenStruct.new(user_id: owner.id)
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/status", params: { session_id: "cs_owner" }, headers: auth_headers_for(owner)
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "paid", body["payment_status"]
    assert_equal "complete", body["status"]
  end

  test "non-owner cannot query another user's checkout session status" do
    owner = create_actor(role: :user)
    attacker = create_actor(role: :user)

    checkout_session = OpenStruct.new(
      payment_status: "paid",
      status: "complete",
      customer_email: owner.email_address,
      metadata: OpenStruct.new(user_id: owner.id)
    )

    Stripe::Checkout::Session.stub(:retrieve, ->(_id) { checkout_session }) do
      get "/api/v1/checkout/status", params: { session_id: "cs_owner" }, headers: auth_headers_for(attacker)
    end

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body.dig("error", "code").to_s
    assert_match(/does not belong/i, body.dig("error", "message"))
  end
end
