class AdminUserSerializer < ActiveModel::Serializer
  attributes :id, :email, :email_address, :name, :role, :status, :email_verified, :email_verified_at

  def email
    object.email_address
  end

  def email_address
    object.email_address
  end

  def email_verified
    object.email_verified?
  end

  def email_verified_at
    object.email_verified_at&.iso8601
  end
end
