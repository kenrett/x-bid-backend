module StorefrontKeyable
  extend ActiveSupport::Concern

  CANONICAL_KEYS = %w[main afterdark marketplace].freeze
  DEFAULT_KEY = "main"

  included do
    before_validation :assign_storefront_key, on: :create

    validates :storefront_key, presence: true
    validates :storefront_key, inclusion: { in: CANONICAL_KEYS }
  end

  private

  def assign_storefront_key
    return if storefront_key.present?

    current = Current.storefront_key.to_s
    if current.present?
      self.storefront_key = current
      return
    end

    self.storefront_key = DEFAULT_KEY
    Rails.logger.warn("storefront_key.defaulted model=#{self.class.name} resolved_to=#{DEFAULT_KEY}")
  rescue StandardError
    self.storefront_key ||= DEFAULT_KEY
  end
end
