# -------------------------------
# Helpers
# -------------------------------
StorefrontConfig = Struct.new(:key, :name, :is_adult, :is_marketplace)

def seed_storefronts!
  puts "Seeding storefronts..."

  # Map legacy seed keys to current schema constraints:
  # biddersweet -> main
  # after_dark  -> afterdark
  # marketplace -> marketplace
  biddersweet = StorefrontConfig.new("main", "BidderSweet", false, false)
  after_dark = StorefrontConfig.new("afterdark", "After Dark", true, false)
  marketplace = StorefrontConfig.new("marketplace", "Marketplace", false, true)

  puts "  - Storefronts:"
  puts "    * #{biddersweet.key}"
  puts "    * #{after_dark.key}"
  puts "    * #{marketplace.key}"

  { biddersweet: biddersweet, after_dark: after_dark, marketplace: marketplace }
end

# -------------------------------
# PRODUCTION SEEDS (Render, etc.)
# -------------------------------
if Rails.env.production?
  AuctionFulfillment.destroy_all
  AuctionSettlement.destroy_all
  Bid.destroy_all
  Auction.destroy_all
  BidPack.destroy_all
  User.destroy_all
  # NOTE: only destroy storefronts in production if you truly want to reset them
  # Storefront.destroy_all

  puts "Seeding production data..."

  # Ensure global maintenance setting exists to prevent race conditions at runtime
  # (MaintenanceSetting model must exist for this to work)
  MaintenanceSetting.find_or_create_by!(key: "global") if defined?(MaintenanceSetting)

  storefronts = seed_storefronts!

  # Users (idempotent)
  admin = User.find_or_create_by!(email_address: "admin@example.com") do |u|
    u.name                  = "Admin"
    u.password              = "password"
    u.password_confirmation = "password"
    u.role                  = :admin
    u.bid_credits           = 1000
  end

  superadmin = User.find_or_create_by!(email_address: "superadmin@example.com") do |u|
    u.name                  = "Superadmin"
    u.password              = "password"
    u.password_confirmation = "password"
    u.role                  = :superadmin
    u.bid_credits           = 1000
  end

  user_one = User.find_or_create_by!(email_address: "user@example.com") do |u|
    u.name                  = "User One"
    u.password              = "password"
    u.password_confirmation = "password"
    u.role                  = :user
    u.bid_credits           = 100
  end

  user_two = User.find_or_create_by!(email_address: "user2@example.com") do |u|
    u.name                  = "User Two"
    u.password              = "password"
    u.password_confirmation = "password"
    u.role                  = :user
    u.bid_credits           = 100
  end

  user_three = User.find_or_create_by!(email_address: "verified_mutating_smoke@example.com") do |u|
    u.name                  = "User Three"
    u.password              = "password"
    u.password_confirmation = "password"
    u.role                  = :user
    u.bid_credits           = 100
    u.email_verified_at     = Time.now
  end


  puts "  - Users seeded:"
  puts "    * #{admin.email_address}"
  puts "    * #{superadmin.email_address}"
  puts "    * #{user_one.email_address}"
  puts "    * #{user_two.email_address}"
  puts "    * #{user_three.email_address}"

  # Bid packs (idempotent)
  bid_packs_data = [
    { name: "The Flirt",      bids: 69,  price: 42.0,  highlight: false, description: "A perfect start to get a feel for the action." },
    { name: "The Rendezvous", bids: 150, price: 82.0,  highlight: false, description: "For the bidder who's ready to commit to the chase." },
    { name: "The All-Nighter", bids: 300, price: 150.0, highlight: true,  description: "Our most popular pack. Dominate the auctions." },
    { name: "The Affair",     bids: 600, price: 270.0, highlight: false, description: "The ultimate arsenal for the serious player. Best value." }
  ]

  bid_packs_data.each do |pack_data|
    pack = BidPack.find_or_create_by!(name: pack_data[:name]) do |p|
      p.bids        = pack_data[:bids]
      p.price       = pack_data[:price]
      p.highlight   = pack_data[:highlight]
      p.description = pack_data[:description]
    end
    puts "  - Bid pack: #{pack.name}"
  end

  if Auction.count == 0
    today = Date.today

    # Put these in After Dark (based on your copy)
    Auction.create!(
      storefront_key: storefronts[:after_dark].key,
      is_adult: storefronts[:after_dark].is_adult,
      is_marketplace: storefronts[:after_dark].is_marketplace,
      title: "Midnight Mystery Gadget",
      description: "A high-end mystery item for night owls who love the thrill.",
      current_price: 0,
      image_url: "https://via.placeholder.com/600x400?text=Midnight+Mystery+Gadget",
      status: Auction.statuses[:active],
      start_date: today + 1.day,
      end_time:   today + 3.days
    )

    Auction.create!(
      storefront_key: storefronts[:after_dark].key,
      is_adult: storefronts[:after_dark].is_adult,
      is_marketplace: storefronts[:after_dark].is_marketplace,
      title: "Weekend Indulgence Bundle",
      description: "Everything you need for an unforgettable weekend.",
      current_price: 0,
      image_url: "https://via.placeholder.com/600x400?text=Weekend+Indulgence",
      status: Auction.statuses[:active],
      start_date: today + 2.days,
      end_time:   today + 4.days
    )

    puts "  - Seeded 2 sample auctions (after_dark)."
  else
    puts "  - Skipped auctions: existing auctions detected (count: #{Auction.count})."
  end

  puts "Production seeds complete."
  return
end

# --------------------------------
# DEVELOPMENT / TEST SEEDS (Faker)
# --------------------------------
puts "Seeding development/test data (destructive)…"

AuctionFulfillment.destroy_all
AuctionSettlement.destroy_all
Bid.destroy_all
Auction.destroy_all
BidPack.destroy_all
User.destroy_all
# Storefront.destroy_all

storefronts = seed_storefronts!

User.create!(
  name: "Admin",
  email_address: "admin@example.com",
  password: "password",
  password_confirmation: "password",
  role: :admin,
  bid_credits: 1000
)

User.create!(
  name: "Superadmin",
  email_address: "superadmin@example.com",
  password: "password",
  password_confirmation: "password",
  role: :superadmin,
  bid_credits: 1000
)

User.create!(
  name: "User One",
  email_address: "user@example.com",
  password: "password",
  password_confirmation: "password",
  role: :user,
  bid_credits: 100
)

User.create!(
  name: "User Two",
  email_address: "user2@example.com",
  password: "password",
  password_confirmation: "password",
  role: :user,
  bid_credits: 100
)

bid_packs_data = [
  { name: "The Flirt",      bids: 69,  price: 42.0,  highlight: false, description: "A perfect start to get a feel for the action." },
  { name: "The Rendezvous", bids: 150, price: 82.0,  highlight: false, description: "For the bidder who's ready to commit to the chase." },
  { name: "The All-Nighter", bids: 300, price: 150.0, highlight: true,  description: "Our most popular pack. Dominate the auctions." },
  { name: "The Affair",     bids: 600, price: 270.0, highlight: false, description: "The ultimate arsenal for the serious player. Best value." }
]
bid_packs_data.each { |pack_data| BidPack.create!(pack_data) }

today = Date.today

# Distribute Faker auctions across storefronts
# (tweak weights however you like)
storefront_pool = (
  [ storefronts[:biddersweet] ] * 12 +
  [ storefronts[:after_dark] ]  * 5 +
  [ storefronts[:marketplace] ] * 3
)

20.times do
  start_date = Faker::Date.between(from: today + 1, to: today + 4)
  sf = storefront_pool.sample

  Auction.create!(
    storefront_key: sf.key,
    is_adult: sf.is_adult,
    is_marketplace: sf.is_marketplace,
    title: Faker::Commerce.product_name,
    description: Faker::Movie.quote,
    current_price: 0,
    image_url: Faker::Avatar.unique.image,
    status: Auction.statuses[:active],
    start_date: start_date,
    end_time: start_date + 2.days
  )
  print "*"
end

puts
puts "Development/test seeds complete."
