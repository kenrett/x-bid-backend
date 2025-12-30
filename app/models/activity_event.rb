class ActivityEvent < ApplicationRecord
  belongs_to :user

  validates :event_type, presence: true
  validates :occurred_at, presence: true
  validates :data, presence: true
end
