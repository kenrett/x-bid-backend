require "test_helper"

class ApiV1AuctionSerializerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "Bidder", email_address: "bidder@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(
      title: "Serialized",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 1.0,
      status: :pending,
      winning_user: @user
    )
  end

  test "serializes public auction with external status and winning user name" do
    json = Api::V1::AuctionSerializer.new(@auction).as_json

    assert_equal "Serialized", json[:title]
    assert_equal "scheduled", json[:status] # pending -> scheduled via external_status
    assert_equal @user.id, json[:winning_user_id]
    assert_equal @user.name, json[:winning_user_name]
    assert json.key?(:current_price)
  end
end
