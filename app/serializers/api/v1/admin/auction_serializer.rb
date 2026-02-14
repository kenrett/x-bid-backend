class Api::V1::Admin::AuctionSerializer < ActiveModel::Serializer
  attributes(
    :id,
    :title,
    :description,
    :start_date,
    :end_time,
    :current_price,
    :image_url,
    :status,
    :storefront_key,
    :is_adult,
    :is_marketplace,
    :winning_user_id,
    :winning_user_name,
    :allowed_admin_transitions
  )

  def image_url
    Uploads::ImageUrl.stable(object.image_url)
  end

  def status
    object.external_status || object.status
  end

  def winning_user_name
    object.winning_user&.name
  end

  def allowed_admin_transitions
    object.allowed_admin_transitions
  end
end
