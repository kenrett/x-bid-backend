require "test_helper"

class PlaceBidTest < ActiveSupport::TestCase
  def setup
    @user1 = User.create!(name: "User 1", email_address: "user1@example.com", password: "password", bid_credits: 10, role: :user)
    @user2 = User.create!(name: "User 2", email_address: "user2@example.com", password: "password", bid_credits: 5, role: :user)

    @auction = Auction.create!(
      title: "Test Auction",
      description: "A test auction.",
      start_date: 1.day.ago,
      end_time: 1.day.from_now,
      current_price: 10.00,
      status: :active
    )
  end

  test "should place a bid successfully" do
    original_price = @auction.current_price
    expected_price = original_price + PlaceBid::BID_INCREMENT

    result = PlaceBid.new(user: @user1, auction: @auction).call

    assert result.success?, "Bid should succeed"
    assert_not_nil result.bid
    assert_equal expected_price, result.bid.amount
    assert_equal @user1.id, result.bid.user_id
    assert_equal 9, @user1.reload.bid_credits
    assert_equal expected_price, @auction.reload.current_price
    assert_equal @user1.id, @auction.reload.winning_user.id
    assert_equal @user1.name, @auction.reload.winning_user.name
  end

  test "should fail if auction is not active" do
    @auction.update!(status: :ended)

    result = PlaceBid.new(user: @user1, auction: @auction).call

    refute result.success?
    assert_equal "Auction is not active", result.error
  end

  test "should fail if user has insufficient bid credits" do
    @user1.update!(bid_credits: 0)

    result = PlaceBid.new(user: @user1, auction: @auction).call

    refute result.success?
    assert_equal "Insufficient bid credits", result.error
  end

  test "should fail and return a specific error if a non-amount validation fails" do
    # We can simulate a different validation failure by stubbing the auction update.
    # Here, we pretend updating the winning_user fails for some reason.
    error_message = "Validation failed: Winning user is invalid"
    @auction.errors.add(:winning_user, "is invalid") # Add a specific error to the object
    exception = ActiveRecord::RecordInvalid.new(@auction)

    # Temporarily redefine the `update!` method on this specific auction instance
    # to raise the desired exception.
    @auction.define_singleton_method(:update!) { |_| raise exception }

    result = PlaceBid.new(user: @user1, auction: @auction).call
    refute result.success?
    assert_equal "Bid could not be placed: #{error_message}", result.error
  end

  test "should extend auction if bid arrives in last 10 seconds" do
    # Set end time to be in the near future to trigger the extension logic.
    @auction.update!(end_time: 5.seconds.from_now) 

    PlaceBid.new(user: @user1, auction: @auction).call

    extended_end_time = @auction.reload.end_time
    expected_end_time = Time.current + PlaceBid::EXTENSION_WINDOW
    assert_in_delta expected_end_time, extended_end_time, 1.second, "Auction end time should be reset to 10 seconds from now"
  end

  test "should handle concurrent bids safely" do
    service1 = PlaceBid.new(user: @user1, auction: @auction)
    service2 = PlaceBid.new(user: @user2, auction: @auction)

    # Use a queue to synchronize the threads.
    # This makes them wait until we're ready to release them simultaneously.
    queue = Queue.new

    bid_results = []
    threads = [
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; bid_results << service1.call } },
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; bid_results << service2.call } }
    ]

    # Wait a moment to ensure both threads are waiting on `queue.pop`.
    sleep 0.1

    # Close the queue to release both threads at once.
    queue.close

    threads.each(&:join)

    success = bid_results.select(&:success?)
    failure = bid_results.reject(&:success?)

    assert_equal 1, success.size, "Exactly one bid should succeed"
    assert_equal 1, failure.size, "Exactly one bid should fail"

    winner = success.first
    loser  = failure.first

    assert_equal winner.bid.amount, @auction.reload.current_price
    assert_match /Another bid was placed first/, loser.error
  end
end
