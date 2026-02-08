require "test_helper"

class StorefrontCapabilitiesTest < ActiveSupport::TestCase
  test "matrix values match expectations" do
    main = Storefront::Capabilities.capabilities_for("main")
    assert_equal false, main[:adult_catalog]
    assert_equal false, main[:requires_age_gate]
    assert_equal false, main[:marketplace_catalog]
    assert_equal false, main[:ugc_marketplace]

    afterdark = Storefront::Capabilities.capabilities_for("afterdark")
    assert_equal true, afterdark[:adult_catalog]
    assert_equal true, afterdark[:requires_age_gate]
    assert_equal false, afterdark[:marketplace_catalog]

    marketplace = Storefront::Capabilities.capabilities_for("marketplace")
    assert_equal false, marketplace[:adult_catalog]
    assert_equal true, marketplace[:marketplace_catalog]
    assert_equal false, marketplace[:ugc_marketplace]
  end

  test "policy relies on capabilities" do
    assert_equal Storefront::Capabilities.adult_catalog_enabled?("afterdark"),
                 Storefront::Policy.can_access_adult_catalog?("afterdark")

    assert Storefront::Capabilities.marketplace_catalog_enabled?("marketplace")
    refute Storefront::Capabilities.marketplace_catalog_enabled?("main")
  end
end
