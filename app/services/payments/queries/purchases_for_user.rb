module Payments
  module Queries
    class PurchasesForUser
      attr_reader :records

      def self.call(user:, relation: Purchase.all)
        new(user: user, relation: relation).call
      end

      def initialize(user:, relation: Purchase.all)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @relation = relation
        @records = []
      end

      def call
        @records = relation
          .includes(:bid_pack)
          .where(user_id: user.id)
          .order(created_at: :desc, id: :desc)
          .to_a

        self
      end

      private

      attr_reader :user, :relation
    end
  end
end
