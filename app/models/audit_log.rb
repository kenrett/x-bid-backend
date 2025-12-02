class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User"
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true
  validates :ip_address, length: { maximum: 255 }, allow_nil: true
  validates :user_agent, length: { maximum: 2000 }, allow_nil: true

  attr_readonly :action, :actor_id, :target_type, :target_id, :payload, :ip_address, :user_agent, :created_at

  before_update :prevent_update

  private

  def prevent_update
    errors.add(:base, "Audit logs are immutable")
    throw :abort
  end
end
