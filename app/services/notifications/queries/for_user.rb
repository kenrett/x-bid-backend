module Notifications
  module Queries
    class ForUser
      attr_reader :records

      def self.call(user:, relation: Notification.all)
        new(user: user, relation: relation).call
      end

      def initialize(user:, relation: Notification.all)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @relation = relation
        @records = nil
      end

      def call
        @records = relation.where(user_id: user.id).order(created_at: :desc, id: :desc)
        self
      end

      private

      attr_reader :user, :relation
    end
  end
end
