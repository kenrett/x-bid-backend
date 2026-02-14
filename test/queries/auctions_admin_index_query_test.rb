require "test_helper"

class AuctionsAdminIndexQueryTest < ActiveSupport::TestCase
  def setup
    @winner = User.create!(name: "Winner", email_address: "winner@example.com", password: "password", bid_credits: 0)
    @active = Auction.create!(
      title: "Active Auction",
      description: "Active description",
      start_date: Time.current,
      end_time: 1.day.from_now,
      current_price: 10.0,
      status: :active,
      storefront_key: "main",
      winning_user: @winner
    )
    @pending = Auction.create!(
      title: "Pending Auction",
      description: "Future sale",
      start_date: 2.days.from_now,
      end_time: 3.days.from_now,
      current_price: 5.0,
      status: :pending,
      storefront_key: "afterdark"
    )
    @ended = Auction.create!(
      title: "Ended Auction",
      description: "Closed item",
      start_date: 3.days.ago,
      end_time: 2.days.ago,
      current_price: 2.0,
      status: :ended,
      storefront_key: "marketplace",
      is_marketplace: true
    )
  end

  test "returns auctions sorted by start_date desc with eager-loaded associations" do
    result = Auctions::Queries::AdminIndex.call(params: {})

    assert_equal [ @pending.id, @active.id, @ended.id ], result.records.map(&:id)
    assert result.records.first.association(:winning_user).loaded?
    assert_equal({ page: 1, per_page: 20, total_pages: 1, total_count: 3 }, result.meta)
  end

  test "filters by status using api-friendly value" do
    result = Auctions::Queries::AdminIndex.call(params: { status: "scheduled" })

    assert_equal [ @pending.id ], result.records.map(&:id)
  end

  test "filters by search term" do
    result = Auctions::Queries::AdminIndex.call(params: { search: "future" })

    assert_equal [ @pending.id ], result.records.map(&:id)
  end

  test "filters by storefront key" do
    result = Auctions::Queries::AdminIndex.call(params: { storefront_key: "marketplace" })

    assert_equal [ @ended.id ], result.records.map(&:id)
  end

  test "returns no records for invalid storefront filter" do
    result = Auctions::Queries::AdminIndex.call(params: { storefront_key: "invalid" })

    assert_empty result.records
    assert_equal 0, result.meta[:total_count]
  end

  test "filters by start_date range" do
    from = 1.day.from_now.iso8601
    to = 4.days.from_now.iso8601

    result = Auctions::Queries::AdminIndex.call(params: { start_date_from: from, start_date_to: to })

    assert_equal [ @pending.id ], result.records.map(&:id)
  end

  test "paginates results and exposes metadata" do
    result = Auctions::Queries::AdminIndex.call(params: { per_page: 1, page: 2, sort: "start_date", direction: "desc" })

    assert_equal [ @active.id ], result.records.map(&:id)
    assert_equal 2, result.meta[:page]
    assert_equal 1, result.meta[:per_page]
    assert_equal 3, result.meta[:total_pages]
    assert_equal 3, result.meta[:total_count]
  end
end
