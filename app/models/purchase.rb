class Purchase < ApplicationRecord
  belongs_to :user
  belongs_to :bid_pack
  belongs_to :ledger_grant_credit_transaction, class_name: "CreditTransaction", optional: true

  include StorefrontKeyable

  STATUSES = %w[
    created
    paid_pending_apply
    applied
    failed
    partially_refunded
    refunded
    voided
  ].freeze
  RECEIPT_STATUSES = { pending: 0, available: 1, unavailable: 2 }.freeze

  enum :receipt_status, RECEIPT_STATUSES, default: :pending

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :stripe_checkout_session_id, uniqueness: true, allow_nil: true
  validates :stripe_payment_intent_id, uniqueness: true, allow_nil: true
  validates :stripe_event_id, uniqueness: true, allow_nil: true

  def refundable_cents
    amount_cents.to_i - refunded_cents.to_i
  end

  def refundable?
    refundable_cents.positive? && !refunded? && !voided? && !failed?
  end

  def refunded?
    status == "refunded"
  end

  def partially_refunded?
    status == "partially_refunded"
  end

  def voided?
    status == "voided"
  end

  def failed?
    status == "failed"
  end
end
