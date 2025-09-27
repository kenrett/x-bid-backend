class BidHistorySerializer < ActiveModel::Serializer
  attributes :id, :amount, :created_at, :username

  def username
    # The user association was eager-loaded in the controller.
    object.user.name || "Anonymous Bidder"
  end
end
