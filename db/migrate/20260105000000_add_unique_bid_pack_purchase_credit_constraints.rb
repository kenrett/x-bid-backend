class AddUniqueBidPackPurchaseCreditConstraints < ActiveRecord::Migration[8.0]
  def change
    add_index(
      :credit_transactions,
      :purchase_id,
      unique: true,
      where: "purchase_id IS NOT NULL AND reason = 'bid_pack_purchase' AND kind = 'grant'",
      name: "uniq_ct_bpp_grant_purchase",
      if_not_exists: true
    )

    add_index(
      :credit_transactions,
      :stripe_payment_intent_id,
      unique: true,
      where: "stripe_payment_intent_id IS NOT NULL AND reason = 'bid_pack_purchase' AND kind = 'grant'",
      name: "uniq_ct_bpp_grant_pi",
      if_not_exists: true
    )

    add_index(
      :credit_transactions,
      :stripe_checkout_session_id,
      unique: true,
      where: "stripe_checkout_session_id IS NOT NULL AND reason = 'bid_pack_purchase' AND kind = 'grant'",
      name: "uniq_ct_bpp_grant_cs",
      if_not_exists: true
    )
  end
end
