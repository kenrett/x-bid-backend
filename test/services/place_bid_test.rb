require "test_helper"

class PlaceBidTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

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
    expected_price = original_price + Auctions::PlaceBid::BID_INCREMENT

    result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call

    assert result.success?, "Bid should succeed"
    assert_equal :ok, result.code
    assert_not_nil result.bid
    assert_equal expected_price, result.bid.amount
    assert_equal @user1.id, result.bid.user_id
    assert_equal 9, @user1.reload.bid_credits
    assert_equal expected_price, @auction.reload.current_price
    assert_equal @user1.id, @auction.reload.winning_user.id
    assert_equal @user1.name, @auction.reload.winning_user.name
    assert_equal 1, MoneyEvent.where(event_type: :bid_spent, source_type: "Bid", source_id: result.bid.id.to_s).count
  end

  test "publishes bid placed domain event" do
    event_args = nil
    Auctions::Events::BidPlaced.stub(:call, ->(auction:, bid:) { event_args = [ auction, bid ] }) do
      result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call
      assert result.success?, "Bid should succeed"
    end

    assert_equal @auction, event_args.first
    assert_instance_of Bid, event_args.last
    assert_equal @auction.id, event_args.last.auction_id
    assert_equal @user1.id, event_args.last.user_id
  end

  test "locks user before auction to follow global lock order" do
    lock_sequence = []
    original_user_lock = @user1.method(:lock!)
    original_auction_lock = @auction.method(:lock!)

    @user1.define_singleton_method(:lock!) do |*args|
      lock_sequence << :user
      original_user_lock.call(*args)
    end

    @auction.define_singleton_method(:lock!) do |*args|
      lock_sequence << :auction
      original_auction_lock.call(*args)
    end

    result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call(broadcast: false)

    assert result.success?, "Bid should succeed"
    assert_equal [ :user, :auction ], lock_sequence.first(2), "User must be locked before auction"
  end

  test "should fail if auction is not active" do
    @auction.update!(status: :ended)

    result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call

    refute result.success?
    assert_equal :auction_not_active, result.code
    assert_equal "Auction is not active", result.error
    assert_equal 0, MoneyEvent.where(event_type: :bid_spent, user: @user1).count
  end

  test "should fail if user has insufficient bid credits" do
    @user1.update!(bid_credits: 0)

    result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call

    refute result.success?
    assert_equal :insufficient_credits, result.code
    assert_equal "Insufficient bid credits", result.error
    assert_equal 0, MoneyEvent.where(event_type: :bid_spent, user: @user1).count
  end

  test "does not publish event on failure" do
    @user1.update!(bid_credits: 0)
    called = false

    Auctions::Events::BidPlaced.stub(:call, ->(**_) { called = true }) do
      result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call
      refute result.success?
    end

    refute called, "Event should not be published when placing bid fails"
  end

  test "does not bypass domain event layer" do
    AuctionChannel.stub(:broadcast_to, ->(*_) { raise "should not broadcast directly" }) do
      Auctions::Events::BidPlaced.stub(:call, ->(auction:, bid:) { [ auction, bid ] }) do
        result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call
        assert result.success?
      end
    end
  end

  test "retries when lock contention occurs" do
    attempts = 0
    original_lock = @auction.method(:lock!)
    @auction.define_singleton_method(:lock!) do
      attempts += 1
      raise ActiveRecord::Deadlocked if attempts == 1
      original_lock.call
    end

    Auctions::Events::BidPlaced.stub(:call, ->(**_) { true }) do
      result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call
      assert result.success?, "Should succeed after retrying a deadlock"
      assert_equal 2, attempts, "Should attempt lock twice"
    end
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

    result = Auctions::PlaceBid.new(user: @user1, auction: @auction).call
    refute result.success?
    assert_equal :bid_invalid, result.code
    assert_equal "Bid could not be placed: #{error_message}", result.error
    assert_equal 0, MoneyEvent.where(event_type: :bid_spent, user: @user1).count
  end

  test "should extend auction if bid arrives in last 10 seconds" do
    travel_to(Time.current) do
      # Set end time to be in the near future to trigger the extension logic.
      @auction.update!(end_time: 5.seconds.from_now)

      Auctions::PlaceBid.new(user: @user1, auction: @auction).call

      extended_end_time = @auction.reload.end_time
      expected_end_time = Time.current + Auctions::PlaceBid::EXTENSION_WINDOW
      assert_in_delta expected_end_time, extended_end_time, 0.5.seconds, "Auction end time should be reset to 10 seconds from now"
    end
  end

  test "should handle concurrent bids safely" do
    service1 = Auctions::PlaceBid.new(user: @user1, auction: @auction)
    service2 = Auctions::PlaceBid.new(user: @user2, auction: @auction)

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
    assert_equal :bid_race_lost, loser.code
    assert_match /Another bid was placed first/, loser.error
    assert_equal 1, MoneyEvent.where(event_type: :bid_spent).count
    assert_equal 1, MoneyEvent.where(event_type: :bid_spent, user_id: winner.bid.user_id).count
    assert_equal(-1, MoneyEvent.where(event_type: :bid_spent).sum(:amount_cents))
  end

  test "only one user wins when bidding concurrently" do
    @auction.update!(current_price: 0.0)
    @user1.update!(bid_credits: 5)
    @user2.update!(bid_credits: 5)

    service1 = Auctions::PlaceBid.new(user: @user1, auction: @auction)
    service2 = Auctions::PlaceBid.new(user: @user2, auction: @auction)

    queue = Queue.new
    results = []
    threads = [
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service1.call } },
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service2.call } }
    ]

    sleep 0.1
    queue.close
    threads.each(&:join)

    winners = results.select(&:success?)
    losers = results.reject(&:success?)

    assert_equal 1, winners.size
    assert_equal 1, losers.size
    assert_equal :bid_race_lost, losers.first.code
    assert_equal winners.first.bid.amount, @auction.reload.current_price
    assert_equal winners.first.bid.user_id, @auction.reload.winning_user_id
  end

  test "credits and current_price stay consistent under concurrent bids" do
    @auction.update!(current_price: 0.0)
    @user1.update!(bid_credits: 5)
    @user2.update!(bid_credits: 5)

    service1 = Auctions::PlaceBid.new(user: @user1, auction: @auction)
    service2 = Auctions::PlaceBid.new(user: @user2, auction: @auction)

    queue = Queue.new
    results = []
    threads = [
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service1.call } },
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service2.call } }
    ]

    sleep 0.1
    queue.close
    threads.each(&:join)

    @auction.reload
    @user1.reload
    @user2.reload

    bids = @auction.bids.order(:created_at)
    assert_equal 1, bids.count, "Only one bid should persist"
    assert_equal bids.last.amount, @auction.current_price
    assert_equal 9, @user1.bid_credits + @user2.bid_credits, "Exactly one credit should be consumed"
    assert_equal 1, MoneyEvent.where(event_type: :bid_spent).count
    assert_equal(-1, MoneyEvent.where(event_type: :bid_spent).sum(:amount_cents))

    winners = results.select(&:success?)
    losers = results.reject(&:success?)
    assert_equal 1, winners.size
    assert_equal 1, losers.size
    assert_equal :bid_race_lost, losers.first.code
  end

  test "concurrent bids by the same user do not double-spend credits and reconcile with MoneyEvents" do
    @auction.update!(current_price: 0.0)
    @user1.update!(bid_credits: 2)

    service1 = Auctions::PlaceBid.new(user: @user1, auction: @auction)
    service2 = Auctions::PlaceBid.new(user: @user1, auction: @auction)

    queue = Queue.new
    results = []
    threads = [
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service1.call } },
      Thread.new { ActiveRecord::Base.connection_pool.with_connection { queue.pop; results << service2.call } }
    ]

    sleep 0.1
    queue.close
    threads.each(&:join)

    @user1.reload
    @auction.reload

    assert_equal 1, @auction.bids.count
    assert_equal 1, MoneyEvent.where(event_type: :bid_spent, user: @user1).count
    assert_equal(-1, MoneyEvent.where(event_type: :bid_spent, user: @user1).sum(:amount_cents))
    assert_equal 1, @user1.bid_credits
  end
end
