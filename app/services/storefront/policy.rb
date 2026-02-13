module Storefront
  module Policy
    module_function

    def can_access_adult_catalog?(storefront_key)
      Storefront::Capabilities.adult_catalog_enabled?(storefront_key)
    end

    def scope_auctions(relation:, storefront_key:)
      key = normalize_storefront_key(storefront_key)

      # TODO: Phase 4 UGC - add curated-inventory rules/metadata (e.g. collections, featured sets)
      # and enforce them here instead of using simple boolean flags.
      scoped = relation.where(storefront_key: key)

      if Storefront::Capabilities.marketplace_catalog_enabled?(key)
        scoped = scoped.where(is_marketplace: true)
      else
        scoped = scoped.where(is_marketplace: false)
      end

      if can_access_adult_catalog?(key)
        scoped
      else
        scoped.where(is_adult: false)
      end
    end

    def normalize_storefront_key(storefront_key)
      key = storefront_key.to_s.strip.downcase
      return StorefrontKeyable::DEFAULT_KEY if key.blank?
      return key if StorefrontKeyable::CANONICAL_KEYS.include?(key)

      StorefrontKeyable::DEFAULT_KEY
    end

    def adult_detail?(auction)
      auction.respond_to?(:is_adult) && auction.is_adult?
    end

    def marketplace_detail?(auction)
      auction.respond_to?(:is_marketplace) && auction.is_marketplace?
    end

    def can_view_adult_detail?(storefront_key:, session_token:, auction:)
      return true unless adult_detail?(auction)
      return false unless can_access_adult_catalog?(storefront_key)

      session_token&.respond_to?(:age_verified_at) && session_token.age_verified_at.present?
    end

    MARKETPLACE_STOREFRONT_KEY = "marketplace"

    def can_view_marketplace_detail?(storefront_key:, auction:)
      return true unless marketplace_detail?(auction)

      storefront_key.to_s == MARKETPLACE_STOREFRONT_KEY
    end
  end
end
