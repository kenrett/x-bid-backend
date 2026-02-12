require "test_helper"

class AuctionsTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/auctions returns stable upload path for image_url" do
    blob = create_authorized_blob
    auction = Auction.create!(
      title: "List Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      image_url: legacy_service_url_for(blob)
    )

    get "/api/v1/auctions"

    assert_response :success
    body = JSON.parse(response.body)
    auctions = body.fetch("auctions")
    auctions = auctions.fetch("auctions") if auctions.is_a?(Hash) && auctions.key?("auctions")
    row = auctions.find { |entry| entry.fetch("id") == auction.id }
    assert_equal "/api/v1/uploads/#{blob.signed_id}", row.fetch("image_url")
  end

  test "GET /api/v1/auctions/:id returns stable upload path for image_url" do
    blob = create_authorized_blob
    auction = Auction.create!(
      title: "Detail Auction",
      description: "Desc",
      start_date: 1.minute.ago,
      end_time: 1.hour.from_now,
      current_price: 1.0,
      status: :active,
      image_url: legacy_service_url_for(blob)
    )

    get "/api/v1/auctions/#{auction.id}"

    assert_response :success
    body = JSON.parse(response.body)
    payload = body["auction"] || body
    assert_equal "/api/v1/uploads/#{blob.signed_id}", payload.fetch("image_url")
  end

  private

  def create_authorized_blob
    user = create_actor(role: :user)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("img-bytes"),
      filename: "auction.jpg",
      content_type: "image/jpeg"
    )
    UploadAuthorization.create!(user: user, blob: blob)
    blob
  end

  def legacy_service_url_for(blob)
    "https://biddersweet-active-storage-prod.s3.us-west-2.amazonaws.com/#{blob.key}?X-Amz-Expires=300"
  end
end
