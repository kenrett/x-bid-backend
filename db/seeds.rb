Auction.destroy_all
BidPack.destroy_all
User.destroy_all

User.create!(
  email_address: "admin@example.com",
  password: "password",
  password_confirmation: "password",
  role: :admin
)

User.create!(
  email_address: "user@example.com",
  password: "password",
  password_confirmation: "password",
  role: :user
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
  Auction.create!(
    title: Faker::Commerce.product_name,
    description: Faker::Movie.quote,
    current_price: Faker::Commerce.price(range: 10..1000).round(2),
    image_url: Faker::Avatar.unique.image,
    status: "inactive",
    start_date: Faker::Date.between(from: today + 1, to: today + 4)
  )
  print "*"
end