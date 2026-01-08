class CreditTransaction < ApplicationRecord
  KINDS = %w[grant debit refund adjustment].freeze

  belongs_to :user
  belongs_to :purchase, optional: true
  belongs_to :auction, optional: true
  belongs_to :admin_actor, class_name: "User", optional: true
  belongs_to :stripe_event, optional: true

  include StorefrontKeyable

  enum :kind, KINDS.index_with(&:itself)

  validates :kind, :reason, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true
  validates :amount, numericality: { only_integer: true, other_than: 0 }
  validate :amount_direction_is_consistent

  # Append-only ledger: entries must never be changed or removed.
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def amount_direction_is_consistent
    return if amount.to_i == 0

    case kind
    when "grant", "refund"
      errors.add(:amount, "must be positive for #{kind}") unless amount.to_i.positive?
    when "debit"
      errors.add(:amount, "must be negative for debit") unless amount.to_i.negative?
    when "adjustment"
      # adjustment may be positive or negative
    end
  end

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "Credit transactions are append-only"
  end
end
