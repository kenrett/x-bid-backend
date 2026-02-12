class Api::V1::AuctionSerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :start_date, :end_time, :current_price, :image_url, :status, :winning_user_id, :winning_user_name

  def image_url
    Uploads::ImageUrl.stable(object.image_url)
  end

  def status
    object.external_status || object.status
  end

  def winning_user_name
    object.winning_user&.name
  end
end
