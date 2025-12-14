# -------------------------------
# PRODUCTION SEEDS (Render, etc.)
# -------------------------------
if Rails.env.production?
  Bid.destroy_all
  Auction.destroy_all
  BidPack.destroy_all
  User.destroy_all

  puts "Seeding production data..."

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

  puts "  - Users seeded:"
  puts "    * #{admin.email_address}"
  puts "    * #{superadmin.email_address}"
  puts "    * #{user_one.email_address}"
  puts "    * #{user_two.email_address}"

  # Bid packs (idempotent)
  bid_packs_data = [
    {
      name: "The Flirt",
      bids: 69,
      price: 42.0,
      highlight: false,
      description: "A perfect start to get a feel for the action."
    },
    {
      name: "The Rendezvous",
      bids: 150,
      price: 82.0,
      highlight: false,
      description: "For the bidder who's ready to commit to the chase."
    },
    {
      name: "The All-Nighter",
      bids: 300,
      price: 150.0,
      highlight: true,
      description: "Our most popular pack. Dominate the auctions."
    },
    {
      name: "The Affair",
      bids: 600,
      price: 270.0,
      highlight: false,
      description: "The ultimate arsenal for the serious player. Best value."
    }
  ]

  bid_packs_data.each do |pack_data|
    pack = BidPack.find_or_create_by!(name: pack_data[:name]) do |p|
      p.bids       = pack_data[:bids]
      p.price      = pack_data[:price]
      p.highlight  = pack_data[:highlight]
      p.description = pack_data[:description]
    end
    puts "  - Bid pack: #{pack.name}"
  end

  if Auction.count == 0
    today = Date.today

    Auction.create!(
      title: "Midnight Mystery Gadget",
      description: "A high-end mystery item for night owls who love the thrill.",
      current_price: 0,
      image_url: "https://via.placeholder.com/600x400?text=Midnight+Mystery+Gadget",
      status: Auction.statuses[:active],
      start_date: today + 1.day,
      end_time:   today + 3.days
    )

    Auction.create!(
      title: "Weekend Indulgence Bundle",
      description: "Everything you need for an unforgettable weekend.",
      current_price: 0,
      image_url: "https://via.placeholder.com/600x400?text=Weekend+Indulgence",
      status: Auction.statuses[:active],
      start_date: today + 2.days,
      end_time:   today + 4.days
    )

    puts "  - Seeded 2 sample auctions."
  else
    puts "  - Skipped auctions: existing auctions detected (count: #{Auction.count})."
  end

  puts "Production seeds complete."
  return
end

# --------------------------------
# DEVELOPMENT / TEST SEEDS (Faker)
# --------------------------------
# Destructive + noisy + Faker-friendly, only outside production.

puts "Seeding development/test data (destructive)…"

Bid.destroy_all
Auction.destroy_all
BidPack.destroy_all
User.destroy_all

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
  {
    name: "The Flirt",
    bids: 69,
    price: 42.0,
    highlight: false,
    description: "A perfect start to get a feel for the action."
  },
  {
    name: "The Rendezvous",
    bids: 150,
    price: 82.0,
    highlight: false,
    description: "For the bidder who's ready to commit to the chase."
  },
  {
    name: "The All-Nighter",
    bids: 300,
    price: 150.0,
    highlight: true,
    description: "Our most popular pack. Dominate the auctions."
  },
  {
    name: "The Affair",
    bids: 600,
    price: 270.0,
    highlight: false,
    description: "The ultimate arsenal for the serious player. Best value."
  }
]

bid_packs_data.each { |pack_data| BidPack.create!(pack_data) }

today = Date.today

20.times do |i|
  start_date = Faker::Date.between(from: today + 1, to: today + 4)
  Auction.create!(
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
