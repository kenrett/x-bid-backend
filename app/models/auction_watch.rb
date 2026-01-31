class AuctionWatch < ApplicationRecord
  belongs_to :user
  belongs_to :auction

  validates :user_id, uniqueness: { scope: :auction_id }

  after_create :log_activity_event

  private

  def log_activity_event
    ActivityEvent.create!(
      user_id: user_id,
      event_type: "auction_watched",
      occurred_at: created_at || Time.current,
      data: {
        auction_id: auction_id,
        watch_id: id
      }
    )
  rescue StandardError => e
    Rails.logger.error("AuctionWatch activity event failed: #{e.class} #{e.message}")
  end
end
