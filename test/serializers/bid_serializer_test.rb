require "test_helper"

class BidSerializerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "User", email_address: "user3@example.com", password: "password", bid_credits: 0)
    @auction = Auction.create!(title: "Auc", description: "Desc", start_date: Time.current, end_time: 1.day.from_now, current_price: 1.0, status: :active)
    @bid = Bid.create!(user: @user, auction: @auction, amount: 2.0)
  end

  test "serializes bid with username" do
    json = BidSerializer.new(@bid).as_json

    assert_equal @bid.id, json[:id]
    assert_equal @user.id, json[:user_id]
    assert_equal @user.name, json[:username]
  end
end
