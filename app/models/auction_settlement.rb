class AuctionSettlement < ApplicationRecord
  RETRY_WINDOW = 24.hours

  belongs_to :auction
  belongs_to :winning_user, class_name: "User", optional: true
  belongs_to :winning_bid, class_name: "Bid", optional: true

  enum :status, {
    pending_payment: 0,
    payment_failed: 1,
    paid: 2,
    no_winner: 3,
    cancelled: 4
  }

  validates :final_price, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :ended_at, presence: true
  validates :auction_id, uniqueness: true
  validates :payment_intent_id, uniqueness: true, allow_nil: true

  def payment_required?
    winning_user.present? && final_price.to_d.positive?
  end

  def retry_window_ends_at
    ended_at + RETRY_WINDOW
  end

  def payment_window_expired?(reference_time: Time.current)
    retry_window_ends_at <= reference_time
  end

  def mark_paid!(payment_intent_id: nil)
    update!(status: :paid, payment_intent_id: payment_intent_id, paid_at: Time.current)
  end

  def mark_payment_failed!(reason: nil)
    update!(status: :payment_failed, failure_reason: reason, failed_at: Time.current)
  end

  def cancel_for_non_payment!(reason: "payment_window_expired")
    update!(status: :cancelled, failure_reason: reason, failed_at: Time.current)
  end
end
