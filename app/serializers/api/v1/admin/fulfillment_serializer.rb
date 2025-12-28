class Api::V1::Admin::FulfillmentSerializer < ActiveModel::Serializer
  attributes :id,
             :auction_settlement_id,
             :user_id,
             :status,
             :shipping_address,
             :shipping_cost_cents,
             :shipping_carrier,
             :tracking_number,
             :metadata,
             :created_at,
             :updated_at
end
