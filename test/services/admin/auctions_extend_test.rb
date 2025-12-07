require "test_helper"
require "minitest/mock"

class AdminAuctionsExtendTest < ActiveSupport::TestCase
  def setup
    @admin = User.create!(name: "Admin", email_address: "admin_extend@example.com", password: "password", role: :admin, bid_credits: 0)
    @user = User.create!(name: "User", email_address: "user_extend@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "extends an auction within the window" do
    auction = Auction.create!(title: "Soon Ending", description: "Desc", start_date: Time.current, end_time: 5.seconds.from_now, current_price: 1.0, status: :active)
    reference_time = Time.current

    result = Admin::Auctions::Extend.new(actor: @admin, auction: auction, window: 10.seconds).call(reference_time: reference_time)

    assert result.ok?
    assert_equal :ok, result.code
    assert_in_delta reference_time + 10.seconds, auction.reload.end_time, 0.001
  end

  test "rejects non-admin actor" do
    auction = Auction.create!(title: "Soon Ending", description: "Desc", start_date: Time.current, end_time: 5.seconds.from_now, current_price: 1.0, status: :active)
    initial_end_time = auction.end_time

    result = Admin::Auctions::Extend.new(actor: @user, auction: auction).call

    refute result.ok?
    assert_equal :forbidden, result.code
    assert_includes result.error, "Admin privileges required"
    assert_in_delta initial_end_time, auction.reload.end_time, 0.001
  end

  test "fails when auction is not within the extend window" do
    auction = Auction.create!(title: "Later Ending", description: "Desc", start_date: Time.current, end_time: 1.hour.from_now, current_price: 1.0, status: :active)

    result = Admin::Auctions::Extend.new(actor: @admin, auction: auction, window: 10.seconds).call

    refute result.ok?
    assert_equal :invalid_state, result.code
  end

  test "returns invalid_auction when update fails" do
    auction = Auction.create!(title: "Failing Update", description: "Desc", start_date: Time.current, end_time: 5.seconds.from_now, current_price: 1.0, status: :active)
    errors = Struct.new(:full_messages).new([ "cannot extend" ])

    auction.stub(:update, false) do
      auction.stub(:errors, errors) do
        result = Admin::Auctions::Extend.new(actor: @admin, auction: auction, window: 10.seconds).call

        refute result.ok?
        assert_equal :invalid_auction, result.code
        assert_equal "cannot extend", result.error
        assert_equal auction, result.record
      end
    end
  end
end
