module Storefront
  module Capabilities
    module_function

    # Centralized storefront capability matrix ensures every check in the app
    # relies on the same source of truth so we can easily reason about which
    # storefronts can see adult/marketplace inventory or require age gates.
    MATRIX = {
      "main" => {
        adult_catalog: false,
        requires_age_gate: false,
        marketplace_catalog: false,
        ugc_marketplace: false
      },
      "afterdark" => {
        adult_catalog: true,
        requires_age_gate: true,
        marketplace_catalog: false,
        ugc_marketplace: false
      },
      "marketplace" => {
        adult_catalog: false,
        requires_age_gate: false,
        marketplace_catalog: true,
        ugc_marketplace: false
      }
    }.freeze

    DEFAULT_KEY = StorefrontKeyable::DEFAULT_KEY

    def capabilities_for(storefront_key)
      normalized = storefront_key.to_s.presence || DEFAULT_KEY
      MATRIX.fetch(normalized, MATRIX[DEFAULT_KEY])
    end

    def adult_catalog_enabled?(storefront_key)
      capabilities_for(storefront_key)[:adult_catalog]
    end

    def requires_age_gate?(storefront_key)
      capabilities_for(storefront_key)[:requires_age_gate]
    end

    def marketplace_catalog_enabled?(storefront_key)
      capabilities_for(storefront_key)[:marketplace_catalog]
    end

    def ugc_marketplace_enabled?(storefront_key)
      capabilities_for(storefront_key)[:ugc_marketplace]
    end
  end
end
