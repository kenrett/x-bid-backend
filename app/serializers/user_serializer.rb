class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :role

  attribute :email_address, key: :emailAddress
  attribute :bid_credits, key: :bidCredits
end
