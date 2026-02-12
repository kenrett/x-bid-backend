require "test_helper"

class ApiV1AdminAuctionSerializerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "Bidder", email_address: "bidder2@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Admin Serialized",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 2.0,
      status: :ended,
      winning_user: @user
    )
  end

  test "serializes admin auction with external status and winning user name" do
    json = Api::V1::Admin::AuctionSerializer.new(@auction).as_json

    assert_equal "Admin Serialized", json[:title]
    assert_equal "complete", json[:status] # ended -> complete via external_status
    assert_equal @user.id, json[:winning_user_id]
    assert_equal @user.name, json[:winning_user_name]
    assert json.key?(:current_price)
    assert_equal [ "inactive" ], json[:allowed_admin_transitions]
  end
end
