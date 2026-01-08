module Storefront
  module Policy
    module_function

    ADULT_CATALOG_STOREFRONT_KEY = "afterdark"

    def can_access_adult_catalog?(storefront_key)
      storefront_key.to_s == ADULT_CATALOG_STOREFRONT_KEY
    end

    def scope_auctions(relation:, storefront_key:)
      return relation if can_access_adult_catalog?(storefront_key)

      relation.where(is_adult: false)
    end

    def adult_detail?(auction)
      auction.respond_to?(:is_adult) && auction.is_adult?
    end

    def can_view_adult_detail?(storefront_key:, session_token:, auction:)
      return true unless adult_detail?(auction)
      return false unless can_access_adult_catalog?(storefront_key)

      session_token&.respond_to?(:age_verified_at) && session_token.age_verified_at.present?
    end
  end
end
