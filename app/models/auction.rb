class Auction < ApplicationRecord
  class InvalidState < StandardError; end

  DETAIL_FIELDS = %i[title description current_price image_url start_date end_time winning_user_id].freeze

  belongs_to :winning_user, class_name: "User", optional: true
  has_many :bids, -> { order(created_at: :desc) }, dependent: :destroy
  has_many :auction_watches, dependent: :destroy
  has_one :settlement, class_name: "AuctionSettlement", dependent: :destroy

  include StorefrontKeyable

  enum :status, { pending: 0, active: 1, ended: 2, cancelled: 3, inactive: 4 }

  validates :title, :description, :start_date, presence: true
  validates :current_price, numericality: { greater_than_or_equal_to: 0 }

  before_destroy :prevent_destroy

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
    assert_state!(pending? || new_record? || inactive?, "Auction must be pending or inactive to schedule")
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
    winner ||= winning_user || winning_bid&.user
    update!(status: :ended, winning_user: winner)
    Auctions::Settle.call(auction: self)
  end

  def winning_bid
    bids.first
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

  def transition_to!(new_status)
    desired = Auctions::Status.to_internal(new_status)
    raise InvalidState, "Unsupported status: #{new_status}" if desired.blank?

    current = status.to_s
    return if desired == current

    case desired
    when "pending"
      unless new_record? || pending? || inactive?
        raise_invalid_transition!(from: current, to: desired)
      end
      schedule!(starts_at: start_date, ends_at: end_time)
    when "active"
      raise_invalid_transition!(from: current, to: desired) unless pending?
      start!
    when "ended"
      raise_invalid_transition!(from: current, to: desired) unless active?
      close!
    when "cancelled"
      unless pending? || active?
        raise_invalid_transition!(from: current, to: desired)
      end
      cancel!
    when "inactive"
      retire!
    else
      raise InvalidState, "Unsupported status: #{new_status}"
    end
  end

  def allowed_admin_transitions
    transitions = []
    transitions << "scheduled" if pending? || inactive? || new_record?
    transitions << "active" if pending?
    transitions << "complete" if active?
    transitions << "cancelled" if pending? || active?
    transitions << "inactive" if !inactive? && !bids.exists?
    transitions
  end

  private

  def prevent_destroy
    errors.add(:base, "Auctions cannot be hard-deleted; retire instead")
    throw(:abort)
  end

  def assert_times!(starts_at, ends_at)
    starts_at = cast_datetime(:start_date, starts_at)
    ends_at = cast_datetime(:end_time, ends_at)
    raise InvalidState, "start_date is required" if starts_at.blank?
    raise InvalidState, "end_time is required" if ends_at.blank?
    raise InvalidState, "end_time must be after start_date" if ends_at <= starts_at
  end

  def cast_datetime(attr_name, value)
    self.class.type_for_attribute(attr_name.to_s).cast(value)
  end

  def assert_state!(condition, message)
    raise InvalidState, message unless condition
  end

  def raise_invalid_transition!(from:, to:)
    raise InvalidState, "Cannot transition auction from #{Auctions::Status.to_api(from)} to #{Auctions::Status.to_api(to)}"
  end
end
