class Api::V1::CreditTransactionSerializer < ActiveModel::Serializer
  attributes :id,
             :created_at,
             :kind,
             :amount,
             :reason,
             :idempotency_key,
             :purchase_id,
             :auction_id,
             :metadata

  def metadata
    object.metadata || {}
  end
end
