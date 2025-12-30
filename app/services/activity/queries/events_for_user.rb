module Activity
  module Queries
    class EventsForUser
      attr_reader :records

      def self.call(user:, relation: ActivityEvent.all)
        new(user: user, relation: relation).call
      end

      def initialize(user:, relation: ActivityEvent.all)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @relation = relation
        @records = []
      end

      def call
        @records = relation
          .where(user_id: user.id)
          .order(occurred_at: :desc, id: :desc)
          .to_a

        self
      end

      private

      attr_reader :user, :relation
    end
  end
end
