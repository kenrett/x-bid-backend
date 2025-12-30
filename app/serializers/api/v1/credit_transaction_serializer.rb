class Api::V1::CreditTransactionSerializer < ActiveModel::Serializer
  attributes :id,
             :created_at,
             :occurred_at,
             :kind,
             :amount,
             :reason,
             :reason_code,
             :reference_type,
             :reference_id,
             :admin_actor_id,
             :idempotency_key,
             :purchase_id,
             :auction_id,
             :metadata

  def occurred_at
    object.created_at
  end

  # Canonical API direction; avoids leaking internal kinds like "grant"/"adjustment".
  def kind
    object.amount.to_i.negative? ? "debit" : "credit"
  end

  # Always positive in the API; direction is carried by `kind`.
  def amount
    object.amount.to_i.abs
  end

  # Human-friendly label for display.
  def reason
    reason_label_for(object.reason)
  end

  # Stable code for programmatic mapping (raw stored reason).
  def reason_code
    object.reason
  end

  def reference_type
    reference&.first
  end

  def reference_id
    reference&.last
  end

  def metadata
    object.metadata || {}
  end

  private

  def reference
    return @reference if defined?(@reference)

    @reference =
      if object.purchase_id.present?
        [ "Purchase", object.purchase_id ]
      elsif object.auction_id.present?
        [ "Auction", object.auction_id ]
      elsif object.stripe_event_id.present?
        [ "StripeEvent", object.stripe_event_id ]
      else
        nil
      end
  end

  def reason_label_for(code)
    return "Bid placed" if code == "bid_placed"
    return "Bid pack purchase" if code == "bid_pack_purchase"
    return "Refund" if code == "purchase_refund_credit_reversal"
    return "Admin adjustment" if code == "admin_adjustment"
    return "Opening balance" if code == "opening balance snapshot"

    raw = code.to_s.tr("_", " ").strip
    return "Unknown" if raw.blank?

    raw.split(/\s+/).map { |word| word[0] ? word[0].upcase + word[1..] : word }.join(" ")
  end
end
