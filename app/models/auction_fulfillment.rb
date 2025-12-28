class AuctionFulfillment < ApplicationRecord
  ALLOWED_STATUS_TRANSITIONS = {
    pending: [ :claimed ],
    claimed: [ :processing ],
    processing: [ :shipped ],
    shipped: [ :complete ],
    complete: []
  }.freeze

  belongs_to :auction_settlement
  belongs_to :user

  after_initialize :set_default_metadata

  enum :status, {
    pending: 0,
    claimed: 1,
    processing: 2,
    shipped: 3,
    complete: 4
  }, default: :pending

  validates :auction_settlement_id, uniqueness: true
  validate :user_matches_settlement_winner
  validate :status_transition_allowed, on: :update

  def transition_to!(new_status)
    update!(status: new_status)
  end

  private

  def user_matches_settlement_winner
    return unless auction_settlement
    if auction_settlement.winning_user_id.blank?
      errors.add(:auction_settlement_id, "must reference a settlement with a winning_user")
      return
    end

    return if user_id == auction_settlement.winning_user_id

    errors.add(:user_id, "must match auction settlement winning_user_id")
  end

  def status_transition_allowed
    return unless will_save_change_to_status?

    previous_raw, next_raw = status_change_to_be_saved
    previous_status = previous_raw.is_a?(String) ? previous_raw : self.class.statuses.key(previous_raw)
    next_status = next_raw.is_a?(String) ? next_raw : self.class.statuses.key(next_raw)
    return if previous_status.blank? || next_status.blank?
    return if previous_status == next_status

    allowed_next = ALLOWED_STATUS_TRANSITIONS.fetch(previous_status.to_sym)
    return if allowed_next.include?(next_status.to_sym)

    errors.add(:status, "invalid transition from #{previous_status} to #{next_status}")
  end

  def set_default_metadata
    self.metadata ||= {}
  end
end
