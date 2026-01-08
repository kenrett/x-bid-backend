module Storefront
  module Policy
    module_function

    ADULT_CATALOG_STOREFRONT_KEY = "afterdark"
    ARTISAN_STOREFRONT_KEY = "artisan"

    def can_access_adult_catalog?(storefront_key)
      storefront_key.to_s == ADULT_CATALOG_STOREFRONT_KEY
    end

    def scope_auctions(relation:, storefront_key:)
      key = storefront_key.to_s

      # TODO: Phase 4 UGC - add curated-inventory rules/metadata (e.g. collections, featured sets)
      # and enforce them here instead of using simple boolean flags.

      scoped = relation

      if key == ARTISAN_STOREFRONT_KEY
        # Artisan storefront is curated inventory only.
        scoped = scoped.where(is_artisan: true)
      else
        # Artisan-only inventory must never leak to other storefronts.
        scoped = scoped.where(is_artisan: false)
      end

      if can_access_adult_catalog?(key)
        scoped
      else
        scoped.where(is_adult: false)
      end
    end

    def adult_detail?(auction)
      auction.respond_to?(:is_adult) && auction.is_adult?
    end

    def artisan_detail?(auction)
      auction.respond_to?(:is_artisan) && auction.is_artisan?
    end

    def can_view_adult_detail?(storefront_key:, session_token:, auction:)
      return true unless adult_detail?(auction)
      return false unless can_access_adult_catalog?(storefront_key)

      session_token&.respond_to?(:age_verified_at) && session_token.age_verified_at.present?
    end

    def can_view_artisan_detail?(storefront_key:, auction:)
      return true unless artisan_detail?(auction)

      storefront_key.to_s == ARTISAN_STOREFRONT_KEY
    end
  end
end
