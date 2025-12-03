class MaintenanceSetting < ApplicationRecord
  GLOBAL_KEY = "global".freeze

  validates :key, presence: true, uniqueness: true

  def self.global
    find_or_create_by!(key: GLOBAL_KEY) do |setting|
      setting.enabled = false
    end
  end
end
