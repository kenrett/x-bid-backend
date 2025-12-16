class StripeEvent < ApplicationRecord
  validates :stripe_event_id, presence: true, uniqueness: true
end
