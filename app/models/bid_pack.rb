class BidPack < ApplicationRecord
  # Overrides the default as_json method to include a calculated `pricePerBid`.
  # This ensures the API response matches the format expected by the front end.
  def as_json(options = {})
    # Get the default hash of attributes from the parent class.
    super(options).merge(
      "pricePerBid" => formatted_price_per_bid
    )
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
end
