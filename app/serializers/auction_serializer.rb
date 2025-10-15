class Api::V1::AuctionSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :start_date, :end_time, :current_price, :image_url, :status, :winning_user_id
end