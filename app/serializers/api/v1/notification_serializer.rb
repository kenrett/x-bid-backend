module Api
  module V1
    class NotificationSerializer < ActiveModel::Serializer
      attributes :id, :kind, :data, :read_at, :created_at
    end
  end
end
