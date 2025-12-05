class BidSerializer < ActiveModel::Serializer
  attributes :id, :amount, :created_at, :user_id, :username

  def username
    object.user.name
  end
end
