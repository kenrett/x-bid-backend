class CreditTransaction < ApplicationRecord
  KINDS = %w[grant debit refund adjustment].freeze

  belongs_to :user
  belongs_to :purchase, optional: true
  belongs_to :auction, optional: true
  belongs_to :admin_actor, class_name: "User", optional: true
  belongs_to :stripe_event, optional: true

  enum :kind, KINDS.index_with(&:itself)

  validates :kind, :reason, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true
  validates :amount, numericality: { only_integer: true, other_than: 0 }

  # Append-only ledger: entries must never be changed or removed.
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "Credit transactions are append-only"
  end
end
