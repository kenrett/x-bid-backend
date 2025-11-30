class Auction < ApplicationRecord
  belongs_to :winning_user, class_name: "User", optional: true
  has_many :bids, dependent: :destroy
  
  enum :status, { pending: 0, active: 1, ended: 2, cancelled: 3, inactive: 4 }

  validates :title, :description, :start_date, presence: true
  validates :current_price, numericality: { greater_than_or_equal_to: 0 }

  # An auction is considered closed if it's not active or its end time has passed.
  def closed?
    status != "active" || (end_time.present? && end_time < Time.current)
  end

  def external_status
    {
      "pending" => "scheduled",
      "ended" => "complete"
    }.fetch(status, status)
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

end
