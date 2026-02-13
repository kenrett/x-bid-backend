require "test_helper"

class StorefrontPolicyTest < ActiveSupport::TestCase
  def setup
    @main_standard = Auction.create!(
      title: "Main Standard",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: false
    )

    @afterdark_standard = Auction.create!(
      title: "Afterdark Standard",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "afterdark",
      is_marketplace: false,
      is_adult: false
    )

    @main_adult = Auction.create!(
      title: "Main Adult",
      description: "Desc",
      start_date: Time.current,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      storefront_key: "main",
      is_marketplace: false,
      is_adult: true
    )
  end

  test "scope_auctions hard-partitions auctions by storefront key" do
    main_ids = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: "main").pluck(:id)
    afterdark_ids = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: "afterdark").pluck(:id)

    assert_includes main_ids, @main_standard.id
    refute_includes main_ids, @afterdark_standard.id

    assert_includes afterdark_ids, @afterdark_standard.id
    refute_includes afterdark_ids, @main_standard.id
  end

  test "scope_auctions still applies capability filters after storefront partitioning" do
    main_ids = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: "main").pluck(:id)
    afterdark_ids = Storefront::Policy.scope_auctions(relation: Auction.all, storefront_key: "afterdark").pluck(:id)

    refute_includes main_ids, @main_adult.id
    refute_includes afterdark_ids, @main_adult.id
  end
end
