class AdminUserSerializer < ActiveModel::Serializer
  attributes :id, :email, :name, :role, :status

  def email
    object.email_address
  end
end
