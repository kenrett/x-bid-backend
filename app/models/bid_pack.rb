class BidPack < ApplicationRecord
  has_many :purchases, dependent: :destroy

  enum :status, { active: 0, retired: 1 }, default: :active

  scope :active, -> { where(status: statuses[:active]) }

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :bids, presence: true, numericality: { greater_than: 0, only_integer: true }

  before_destroy :prevent_destroy
  before_save :sync_active_flag

  # Overrides the default as_json method to include a calculated `pricePerBid`.
  # This ensures the API response matches the format expected by the front end.
  def as_json(options = {})
    # Get the default hash of attributes from the parent class.
    super(options).merge(
      "pricePerBid" => formatted_price_per_bid
    )
  end

  def active=(value)
    cast_value = ActiveRecord::Type::Boolean.new.cast(value)
    self.status = cast_value ? "active" : "retired"
    super(cast_value)
  end

  private

  def formatted_price_per_bid
    # Avoid division by zero if bids is 0 or nil.
    return "$0.00" if bids.to_i.zero?

    # To safely check for a remainder, we should work with integers (cents).
    price_in_cents = (price * 100).to_i
    is_approximate = price_in_cents % bids != 0

    prefix = is_approximate ? "~" : ""
    # Use ActiveSupport::NumberHelper, which is safer to call from a model.
    prefix + ActiveSupport::NumberHelper.number_to_currency(price / bids, precision: 2)
  end

  def prevent_destroy
    errors.add(:base, "Bid packs cannot be hard-deleted; retire instead")
    throw(:abort)
  end

  def sync_active_flag
    # Keep legacy boolean column in sync for callers still reading `active`.
    self.active = status == "active"
  end
end
