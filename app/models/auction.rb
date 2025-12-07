class Auction < ApplicationRecord
  class InvalidState < StandardError; end

  DETAIL_FIELDS = %i[title description current_price image_url start_date end_time winning_user_id].freeze

  belongs_to :winning_user, class_name: "User", optional: true
  has_many :bids, -> { order(created_at: :desc) }, dependent: :destroy

  enum :status, { pending: 0, active: 1, ended: 2, cancelled: 3, inactive: 4 }

  validates :title, :description, :start_date, presence: true
  validates :current_price, numericality: { greater_than_or_equal_to: 0 }

  before_destroy :prevent_destroy

  # Accept external status values and map them to internal enum keys.
  def status=(value)
    mapped = Auctions::Status.from_api(value) || value
    super(mapped)
  end

  def self.normalize_status(value)
    Auctions::Status.from_api(value)
  end

  # An auction is considered closed if it's not active or its end time has passed.
  def closed?
    status != "active" || (end_time.present? && end_time < Time.current)
  end

  def external_status
    Auctions::Status.to_api(status)
  end

  def as_json(options = {})
    base = super(
      {
        only: [
          :id,
          :title,
          :description,
          :current_price,
          :image_url,
          :status,
          :start_date,
          :end_time
        ]
      }.merge(options || {})
    )

    base.merge(
      "status" => external_status,
      "highest_bidder_id" => winning_user_id,
      "winning_user_name" => winning_user&.name
    )
  end

  # Checks if the auction is ending within a given duration.
  def ends_within?(duration)
    return false unless end_time
    (Time.current..Time.current + duration).cover?(end_time)
  end

  def update_details!(attrs)
    attrs = attrs.symbolize_keys.slice(*DETAIL_FIELDS)
    raise ArgumentError, "No permitted attributes provided" if attrs.empty?

    if attrs.key?(:start_date) || attrs.key?(:end_time)
      starts_at = attrs.fetch(:start_date, start_date)
      ends_at = attrs.fetch(:end_time, end_time)
      assert_times!(starts_at, ends_at)
    end

    update!(attrs)
  end

  def schedule!(starts_at:, ends_at:)
    assert_state!(pending? || new_record?, "Auction must be pending to schedule")
    assert_times!(starts_at, ends_at)

    update!(start_date: starts_at, end_time: ends_at, status: :pending)
  end

  def start!
    assert_state!(pending?, "Auction must be pending to start")
    update!(status: :active, start_date: start_date || Time.current)
  end

  def extend_end_time!(by:, reference_time: Time.current)
    assert_state!(active?, "Auction must be active to extend")
    assert_state!(ends_within?(by), "Auction not within extend window")

    update!(end_time: reference_time + by)
  end

  def close!(winner: nil)
    assert_state!(active?, "Auction must be active to close")
    update!(status: :ended, winning_user: winner)
  end

  def cancel!
    assert_state!(pending? || active?, "Auction cannot be cancelled once finished")
    update!(status: :cancelled)
  end

  def retire!
    assert_state!(!inactive?, "Auction already inactive")
    assert_state!(!bids.exists?, "Cannot retire an auction that has bids.")

    update!(status: :inactive)
  end

  private

  def prevent_destroy
    errors.add(:base, "Auctions cannot be hard-deleted; retire instead")
    throw(:abort)
  end

  def assert_times!(starts_at, ends_at)
    raise InvalidState, "start_date is required" if starts_at.blank?
    raise InvalidState, "end_time is required" if ends_at.blank?
    raise InvalidState, "end_time must be after start_date" if ends_at <= starts_at
  end

  def assert_state!(condition, message)
    raise InvalidState, message unless condition
  end
end
