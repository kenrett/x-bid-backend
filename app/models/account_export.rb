class AccountExport < ApplicationRecord
  belongs_to :user

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  validates :requested_at, presence: true
  validate :payload_present_when_ready

  private

  def payload_present_when_ready
    return unless ready?

    errors.add(:payload, "can't be blank") if payload.blank?
  end
end
