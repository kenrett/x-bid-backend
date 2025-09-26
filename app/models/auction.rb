class Auction < ApplicationRecord
  belongs_to :winning_user, class_name: "User", optional: true
  has_many :bids, dependent: :destroy
  
  enum :status, { pending: 0, active: 1, ended: 2, cancelled: 3 }

  validates :title, :description, :start_date, presence: true
  validates :current_price, numericality: { greater_than_or_equal_to: 0 }

  # An auction is considered closed if it's not active or its end time has passed.
  def closed?
    status != "active" || (end_time.present? && end_time < Time.current)
  end
end
