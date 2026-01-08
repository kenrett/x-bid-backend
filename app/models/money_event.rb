class MoneyEvent < ApplicationRecord
  EVENT_TYPES = %w[purchase bid_spent refund admin_adjustment].freeze

  belongs_to :user
  belongs_to :source, polymorphic: true, optional: true

  include StorefrontKeyable

  enum :event_type, EVENT_TYPES.index_with(&:itself), validate: true

  validates :amount_cents, numericality: { only_integer: true }
  validates :currency, :occurred_at, presence: true

  # Append-only ledger: entries must never be changed or removed.
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "Money events are append-only"
  end
end
